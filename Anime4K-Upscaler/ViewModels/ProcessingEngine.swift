// Anime4K-Upscaler/ViewModels/ProcessingEngine.swift
// Manages FFmpeg process lifecycle, progress parsing, and power assertion.

import Foundation
import IOKit.pwr_mgt
import Observation
import Metal
import CoreML
import Vision
import CoreGraphics

/// Manages the lifecycle of FFmpeg processes for video upscaling jobs.
/// Handles process spawning, stderr parsing for progress, cancellation,
/// and system sleep prevention via IOKit power assertions.
@MainActor @Observable
final class ProcessingEngine {

    // MARK: - Observable State

    var isProcessing: Bool = false
    var currentJobIndex: Int = 0
    var totalJobs: Int = 0
    var overallProgress: Double = 0.0

    // MARK: - Internal State

    @ObservationIgnored private var currentDecodeProcess: Process?
    @ObservationIgnored private var currentEncodeProcess: Process?
    @ObservationIgnored private var powerAssertionID: IOPMAssertionID = 0
    @ObservationIgnored private var hasPowerAssertion: Bool = false
    @ObservationIgnored private var cancellationRequested: Bool = false
    @ObservationIgnored private var activityToken: NSObjectProtocol?

    /// Minimum interval between UI updates from pipe handlers.
    private static let uiUpdateIntervalMs: Int = 100 // 10 Hz cap

    /// Recommended in-flight worker hint when ANE is available.
    private static let neuralWorkerHint: Int = 3

    // MARK: - Process Execution

    /// Execute a batch of processing jobs sequentially.
    /// - Parameter jobs: Array of ProcessingJob instances to execute in order.
    func executeBatch(jobs: [ProcessingJob]) async {
        guard !jobs.isEmpty else { return }

        isProcessing = true
        totalJobs = jobs.count
        currentJobIndex = 0
        cancellationRequested = false

        acquirePowerAssertion()
        beginAppNapPrevention()

        for (index, job) in jobs.enumerated() {
            if cancellationRequested { break }

            currentJobIndex = index + 1
            await executeJob(job)
            updateOverallProgress(completedIndex: index, total: jobs.count)
        }

        endAppNapPrevention()
        releasePowerAssertion()
        isProcessing = false
    }

    /// Execute a single processing job.
    /// - Parameter job: The ProcessingJob to execute.
    private func executeJob(_ job: ProcessingJob) async {
        guard let ffmpegURL = FFmpegLocator.ffmpegURL,
              FileManager.default.isExecutableFile(atPath: ffmpegURL.path) else {
            job.state = .failed
            job.errorMessage = "FFmpeg binary not found in app bundle."
            return
        }

        guard let ffprobeURL = FFmpegLocator.ffprobeURL,
              FileManager.default.isExecutableFile(atPath: ffprobeURL.path) else {
            job.state = .failed
            job.errorMessage = "FFprobe binary not found in app bundle."
            return
        }

        let metalSourceDir = FFmpegLocator.metalSourceDirectoryPath
        guard !metalSourceDir.isEmpty else {
            job.state = .failed
            job.errorMessage = "Translated .metal sources not found (missing metal_sources directory)."
            return
        }

        guard let outputURL = job.outputURL else {
            job.state = .failed
            job.errorMessage = "Output URL could not be determined."
            return
        }

        guard let streamInfo = Self.probeVideoStreamInfo(
            ffprobeURL: ffprobeURL,
            inputURL: job.file.url,
            environment: FFmpegLocator.processEnvironment()
        ) else {
            job.state = .failed
            job.errorMessage = "Failed to probe input stream metadata."
            return
        }

        let shaderFiles = job.configuration.mode.resolvedMetalShaderSources(for: job.configuration.resolution)
        guard !shaderFiles.isEmpty else {
            job.state = .failed
            job.errorMessage = "Resolved shader chain is empty for selected mode/resolution."
            return
        }

        let effectiveScale = max(1, job.configuration.mode.resolvedScaleFactor(for: job.configuration.resolution))
        let targetOutputWidth = max(1, streamInfo.width * effectiveScale)
        let targetOutputHeight = max(1, streamInfo.height * effectiveScale)

        let requestedBackend = A4KComputeBackend.resolve(from: ProcessInfo.processInfo.environment)

        let processor: Anime4KOfflineProcessor
        do {
            processor = try Anime4KOfflineProcessor(
                shaderFileNames: shaderFiles,
                targetOutputScale: Float(effectiveScale),
                metalSourceDirectoryPath: metalSourceDir,
                computeBackend: requestedBackend
            )
        } catch {
            job.state = .failed
            job.errorMessage = error.localizedDescription
            return
        }

        let decodeArguments = Self.buildDecodeArguments(inputURL: job.file.url)
        let encodeArguments = Self.buildEncodeArguments(
            inputURL: job.file.url,
            outputURL: outputURL,
            streamInfo: streamInfo,
            outputWidth: targetOutputWidth,
            outputHeight: targetOutputHeight,
            configuration: job.configuration
        )

        let totalDuration = streamInfo.durationSeconds ?? job.file.durationSeconds ?? 0

        job.state = .running
        job.progress = 0.0
        job.startDate = Date()
        job.appendLog("$ ffmpeg \(decodeArguments.joined(separator: " "))")
        job.appendLog("$ ffmpeg \(encodeArguments.joined(separator: " "))")
        job.appendLog("[backend] requested=\(processor.requestedBackend.rawValue) active=\(processor.activeBackend.rawValue)")

        if ProcessInfo.processInfo.environment["A4K_ENABLE_NEURAL_ASSIST"] != "0" {
            let neural = Self.neuralAssistStatus()
            let engineStatus = neural.hasNeuralEngine ? "detected" : "not_detected"
            let warmupStatus = neural.warmupSucceeded ? "ok" : "skipped_or_failed"
            job.appendLog("[neural] engine=\(engineStatus) warmup=\(warmupStatus) worker_hint=\(Self.neuralWorkerHint)")
        }

        let capturedFFmpegURL = ffmpegURL
        let capturedDecodeArgs = decodeArguments
        let capturedEncodeArgs = encodeArguments
        let capturedEnvironment = FFmpegLocator.processEnvironment()
        let inputWidth = streamInfo.width
        let inputHeight = streamInfo.height
        let outputWidth = targetOutputWidth
        let outputHeight = targetOutputHeight
        let fps = max(0.0001, streamInfo.fps)
        let throttleSeconds = Double(Self.uiUpdateIntervalMs) / 1000.0

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            nonisolated(unsafe) var didResume = false
            func safeResume() {
                guard !didResume else { return }
                didResume = true
                continuation.resume()
            }

            Task.detached(priority: .userInitiated) { [weak self] in
                let decodeProcess = Process()
                decodeProcess.executableURL = capturedFFmpegURL
                decodeProcess.arguments = capturedDecodeArgs
                decodeProcess.environment = capturedEnvironment

                let decodeOutPipe = Pipe()
                let decodeErrPipe = Pipe()
                decodeProcess.standardOutput = decodeOutPipe
                decodeProcess.standardError = decodeErrPipe

                let encodeProcess = Process()
                encodeProcess.executableURL = capturedFFmpegURL
                encodeProcess.arguments = capturedEncodeArgs
                encodeProcess.environment = capturedEnvironment

                let encodeInPipe = Pipe()
                let encodeErrPipe = Pipe()
                encodeProcess.standardInput = encodeInPipe
                encodeProcess.standardError = encodeErrPipe

                let decodeErrHandle = decodeErrPipe.fileHandleForReading
                let encodeErrHandle = encodeErrPipe.fileHandleForReading
                let decodeOutputHandle = decodeOutPipe.fileHandleForReading
                let encodeInputHandle = encodeInPipe.fileHandleForWriting

                func cleanupPipes() {
                    decodeErrHandle.readabilityHandler = nil
                    encodeErrHandle.readabilityHandler = nil
                    try? decodeErrHandle.close()
                    try? encodeErrHandle.close()
                    try? decodeOutputHandle.close()
                    try? encodeInputHandle.close()
                }

                decodeErrHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty,
                          let text = String(data: data, encoding: .utf8) else { return }
                    let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
                    if lines.isEmpty { return }
                    Task { @MainActor in
                        for line in lines {
                            job.appendLog("[decode] \(line)")
                        }
                    }
                }

                encodeErrHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty,
                          let text = String(data: data, encoding: .utf8) else { return }
                    let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
                    if lines.isEmpty { return }
                    Task { @MainActor in
                        for line in lines {
                            job.appendLog("[encode] \(line)")
                        }
                    }
                }

                do {
                    try encodeProcess.run()
                    try decodeProcess.run()
                } catch {
                    cleanupPipes()
                    await MainActor.run { [weak self] in
                        self?.currentDecodeProcess = nil
                        self?.currentEncodeProcess = nil
                        job.processHandle = nil
                        job.state = .failed
                        job.errorMessage = "Failed to launch FFmpeg pipeline: \(error.localizedDescription)"
                        job.endDate = Date()
                        job.appendLog("[error] failed to launch pipeline: \(error.localizedDescription)")
                        safeResume()
                    }
                    return
                }

                await MainActor.run { [weak self] in
                    self?.currentDecodeProcess = decodeProcess
                    self?.currentEncodeProcess = encodeProcess
                    job.processHandle = encodeProcess
                }

                let inputFrameBytes = inputWidth * inputHeight * 4
                var outputFrameData = Data(count: max(1, outputWidth * outputHeight * 4))
                let wallStart = Date()
                var lastUIUpdate = wallStart
                var frameIndex = 0
                var processingError: String?

                while true {
                    let shouldCancel = await MainActor.run { [weak self] in
                        self?.cancellationRequested ?? true
                    }
                    if shouldCancel { break }

                    let frameData: Data?
                    do {
                        frameData = try Self.readExactly(handle: decodeOutputHandle, byteCount: inputFrameBytes)
                    } catch {
                        processingError = "Failed reading decoded frame stream: \(error.localizedDescription)"
                        break
                    }

                    guard let frameData else { break }
                    if frameData.count != inputFrameBytes {
                        processingError = "Truncated frame from decoder (got \(frameData.count), expected \(inputFrameBytes))."
                        break
                    }

                    do {
                        let dims = try processor.processFrame(
                            inputFrame: frameData,
                            inputWidth: inputWidth,
                            inputHeight: inputHeight,
                            nativeWidth: inputWidth,
                            nativeHeight: inputHeight,
                            targetOutputWidth: outputWidth,
                            targetOutputHeight: outputHeight,
                            outputFrame: &outputFrameData
                        )

                        if dims.width != outputWidth || dims.height != outputHeight {
                            processingError = "Unexpected Metal output dimensions \(dims.width)x\(dims.height); expected \(outputWidth)x\(outputHeight)."
                            break
                        }
                    } catch {
                        processingError = "Metal frame processing failed: \(error.localizedDescription)"
                        break
                    }

                    do {
                        try encodeInputHandle.write(contentsOf: outputFrameData)
                    } catch {
                        processingError = "Failed writing encoded frame stream: \(error.localizedDescription)"
                        break
                    }

                    frameIndex += 1
                    let now = Date()
                    if now.timeIntervalSince(lastUIUpdate) >= throttleSeconds {
                        let elapsed = max(now.timeIntervalSince(wallStart), 0.001)
                        let processedSeconds = Double(frameIndex) / fps
                        let progress = totalDuration > 0 ? min(processedSeconds / totalDuration, 1.0) : 0.0
                        let speed = processedSeconds / elapsed
                        let realtimeFPS = Double(frameIndex) / elapsed
                        let ffmpegTime = Self.formatFFmpegTime(seconds: processedSeconds)
                        lastUIUpdate = now

                        await MainActor.run {
                            job.currentFrame = frameIndex
                            job.currentTime = ffmpegTime
                            job.progress = progress
                            job.speed = String(format: "%.2fx", speed)
                            job.fps = String(format: "%.1f", realtimeFPS)
                        }
                    }
                }

                try? encodeInputHandle.close()

                let cancelled = await MainActor.run { [weak self] in
                    self?.cancellationRequested ?? true
                }

                if cancelled {
                    if decodeProcess.isRunning { decodeProcess.terminate() }
                    if encodeProcess.isRunning { encodeProcess.terminate() }
                }

                decodeProcess.waitUntilExit()
                encodeProcess.waitUntilExit()
                cleanupPipes()

                await MainActor.run { [weak self] in
                    job.endDate = Date()
                    self?.currentDecodeProcess = nil
                    self?.currentEncodeProcess = nil
                    job.processHandle = nil

                    if cancelled {
                        job.state = .cancelled
                        job.appendLog("[cancel] processing cancelled by user")
                    } else if let processingError {
                        job.state = .failed
                        job.errorMessage = processingError
                        job.appendLog("[error] \(processingError)")
                    } else if decodeProcess.terminationStatus == 0 && encodeProcess.terminationStatus == 0 {
                        job.state = .completed
                        job.progress = 1.0
                        job.appendLog("[done] processing completed successfully")
                    } else {
                        let msg = "FFmpeg pipeline exited with decode=\(decodeProcess.terminationStatus), encode=\(encodeProcess.terminationStatus)"
                        job.state = .failed
                        job.errorMessage = msg
                        job.appendLog("[error] \(msg)")
                    }

                    safeResume()
                }
            }
        }
    }

    private struct VideoStreamInfo: Sendable {
        let width: Int
        let height: Int
        let fps: Double
        let fpsArgument: String
        let durationSeconds: Double?
    }

    private static func probeVideoStreamInfo(
        ffprobeURL: URL,
        inputURL: URL,
        environment: [String: String]
    ) -> VideoStreamInfo? {
        let process = Process()
        process.executableURL = ffprobeURL
        process.arguments = [
            "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=width,height,avg_frame_rate,r_frame_rate",
            "-show_entries", "format=duration",
            "-of", "json",
            inputURL.path
        ]
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let streams = root["streams"] as? [[String: Any]],
              let stream = streams.first,
              let width = stream["width"] as? Int,
              let height = stream["height"] as? Int else {
            return nil
        }

        let avgFPSRaw = stream["avg_frame_rate"] as? String
        let rFPSRaw = stream["r_frame_rate"] as? String

        let avgFPS = parseFPS(avgFPSRaw)
        let rFPS = parseFPS(rFPSRaw)
        let fps = max(0.0001, avgFPS ?? rFPS ?? 24.0)

        let fpsArgCandidate = (avgFPSRaw?.isEmpty == false ? avgFPSRaw : rFPSRaw) ?? "24/1"
        let fpsArgument = fpsArgCandidate == "0/0" ? "24/1" : fpsArgCandidate

        var duration: Double?
        if let format = root["format"] as? [String: Any],
           let durationString = format["duration"] as? String,
           let parsed = Double(durationString), parsed.isFinite, parsed > 0 {
            duration = parsed
        }

        return VideoStreamInfo(
            width: width,
            height: height,
            fps: fps,
            fpsArgument: fpsArgument,
            durationSeconds: duration
        )
    }

    private static func parseFPS(_ raw: String?) -> Double? {
        guard let raw, !raw.isEmpty, raw != "0/0" else { return nil }

        if raw.contains("/") {
            let parts = raw.split(separator: "/")
            guard parts.count == 2,
                  let numerator = Double(parts[0]),
                  let denominator = Double(parts[1]),
                  denominator != 0 else {
                return nil
            }
            return numerator / denominator
        }

        if let value = Double(raw), value.isFinite, value > 0 {
            return value
        }

        return nil
    }

    private static func buildDecodeArguments(inputURL: URL) -> [String] {
        [
            "-hide_banner",
            "-loglevel", "warning",
            "-nostdin",
            "-i", inputURL.path,
            "-map", "0:v:0",
            "-an",
            "-sn",
            "-vf", "format=bgra",
            "-f", "rawvideo",
            "-pix_fmt", "bgra",
            "pipe:1"
        ]
    }

    private static func buildEncodeArguments(
        inputURL: URL,
        outputURL: URL,
        streamInfo: VideoStreamInfo,
        outputWidth: Int,
        outputHeight: Int,
        configuration: JobConfiguration
    ) -> [String] {
        var args: [String] = [
            "-y",
            "-hide_banner",
            "-loglevel", "warning",
            "-nostdin",
            "-f", "rawvideo",
            "-pix_fmt", "bgra",
            "-s", "\(outputWidth)x\(outputHeight)",
            "-r", streamInfo.fpsArgument,
            "-i", "pipe:0",
            "-i", inputURL.path,
            "-map", "0:v:0",
            "-map", "1:a?",
            "-map", "1:s?",
            "-c:v", configuration.codec.encoderName,
            "-c:a", "copy",
            "-c:s", "copy"
        ]

        switch configuration.codec {
        case .hevcVideoToolbox:
            args.append(contentsOf: [
                "-profile:v", "main10",
                "-pix_fmt", configuration.codec.pixelFormat,
                "-prio_speed", "1",
                "-allow_sw", "1",
                "-bf", "7"
            ])

            if configuration.compression.isFixedBitrate {
                let mbps = configuration.compression.bitrateMbps
                let bRate = "\(mbps * 1000)k"
                let minRate = "\(Int(Double(mbps) * 900))k"
                let maxRate = "\(Int(Double(mbps) * 1100))k"
                let bufSize = "\(Int(Double(mbps) * 1500))k"
                args.append(contentsOf: [
                    "-b:v", bRate,
                    "-minrate", minRate,
                    "-maxrate", maxRate,
                    "-bufsize", bufSize
                ])
            } else {
                let qVal = configuration.compression.qualityValue(for: .hevcVideoToolbox)
                args.append(contentsOf: ["-q:v", "\(qVal)"])
            }

        case .svtAV1:
            args.append(contentsOf: [
                "-pix_fmt", configuration.codec.pixelFormat,
                "-preset", "6",
                "-svtav1-params", "tune=0"
            ])

            if configuration.compression.isFixedBitrate {
                let mbps = configuration.compression.bitrateMbps
                let bRate = "\(mbps * 1000)k"
                let maxRate = "\(Int(Double(mbps) * 1100))k"
                let bufSize = "\(Int(Double(mbps) * 1500))k"
                args.append(contentsOf: [
                    "-b:v", bRate,
                    "-maxrate", maxRate,
                    "-bufsize", bufSize
                ])
            } else {
                let crfVal = configuration.compression.qualityValue(for: .svtAV1)
                args.append(contentsOf: ["-crf", "\(crfVal)"])
            }
        }

        if configuration.longGOPEnabled {
            args.append(contentsOf: ["-g", "240"])
        }

        args.append(outputURL.path)
        return args
    }

    nonisolated private static func readExactly(handle: FileHandle, byteCount: Int) throws -> Data? {
        guard byteCount > 0 else { return Data() }

        var data = Data(capacity: byteCount)
        while data.count < byteCount {
            let needed = byteCount - data.count
            let chunk = try handle.read(upToCount: needed) ?? Data()
            if chunk.isEmpty {
                return data.isEmpty ? nil : data
            }
            data.append(chunk)
        }

        return data
    }

    nonisolated private static func formatFFmpegTime(seconds: Double) -> String {
        let clamped = max(0, seconds)
        let hours = Int(clamped) / 3600
        let minutes = (Int(clamped) % 3600) / 60
        let secs = clamped - Double(hours * 3600 + minutes * 60)
        return String(format: "%02d:%02d:%05.2f", hours, minutes, secs)
    }

    private static func neuralAssistStatus() -> (hasNeuralEngine: Bool, warmupSucceeded: Bool) {
        guard #available(macOS 13.0, *) else {
            return (false, false)
        }

        guard let neuralDevice = MLComputeDevice.allComputeDevices.first(where: {
            String(describing: $0).contains("MLNeuralEngineComputeDevice")
        }) else {
            return (false, false)
        }

        guard #available(macOS 14.0, *) else {
            return (true, false)
        }

        let request = VNGenerateImageFeaturePrintRequest()
        request.setComputeDevice(neuralDevice, for: .main)
        let handler = VNImageRequestHandler(cgImage: syntheticProbeImage(width: 96, height: 96), options: [:])

        do {
            try handler.perform([request])
            return (true, true)
        } catch {
            return (true, false)
        }
    }

    private static func syntheticProbeImage(width: Int, height: Int) -> CGImage {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * bytesPerPixel
                let v = UInt8((x ^ y) & 0xFF)
                pixels[i] = v
                pixels[i + 1] = UInt8(255 &- v)
                pixels[i + 2] = UInt8((x + y) & 0xFF)
                pixels[i + 3] = 255
            }
        }

        let provider = CGDataProvider(data: NSData(bytes: &pixels, length: pixels.count))!
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    // MARK: - Cancellation

    /// Cancel the currently running job and abort the batch.
    func cancelAll() {
        cancellationRequested = true
        if let decode = currentDecodeProcess, decode.isRunning {
            decode.terminate()
        }
        if let encode = currentEncodeProcess, encode.isRunning {
            encode.terminate()
        }
    }

    /// Cancel a specific job if it is currently running.
    func cancelJob(_ job: ProcessingJob) {
        cancellationRequested = true
        if let process = job.processHandle, process.isRunning {
            process.terminate()
        }
        if let decode = currentDecodeProcess, decode.isRunning {
            decode.terminate()
        }
    }

    // MARK: - Overall Progress

    private func updateOverallProgress(completedIndex: Int, total: Int) {
        overallProgress = Double(completedIndex + 1) / Double(total)
    }

    // MARK: - Power Assertion (Caffeinate Equivalent)

    /// Prevent the system from sleeping during processing.
    private func acquirePowerAssertion() {
        guard !hasPowerAssertion else { return }
        let reason = "Anime4K Upscaler is processing video" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &powerAssertionID
        )
        hasPowerAssertion = (result == kIOReturnSuccess)
    }

    /// Release the sleep prevention assertion.
    private func releasePowerAssertion() {
        guard hasPowerAssertion else { return }
        IOPMAssertionRelease(powerAssertionID)
        hasPowerAssertion = false
        powerAssertionID = 0
    }

    // MARK: - App Nap Prevention

    private func beginAppNapPrevention() {
        guard activityToken == nil else { return }
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Anime4K video upscaling in progress"
        )
    }

    private func endAppNapPrevention() {
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
    }
}
