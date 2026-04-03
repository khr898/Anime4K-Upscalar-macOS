// Anime4K-Upscaler/ViewModels/ProcessingEngine.swift
// Manages FFmpeg process lifecycle, progress parsing, and power assertion.

import Foundation
import IOKit.pwr_mgt
import Observation
import Metal
import AVFoundation
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
    /// Hard cap to bound memory pressure while still allowing strong parallelism.
    private static let maxWorkerCount: Int = 8
    /// Hard cap for queued frames waiting on worker/GPU completion.
    private static let maxPipelineDepth: Int = 16

    private enum DecodeBackend {
        case ffmpeg
        case videoToolbox

        var logTag: String {
            switch self {
            case .ffmpeg:
                return "ffmpeg"
            case .videoToolbox:
                return "videotoolbox"
            }
        }
    }

    private enum DecodedFrame {
        case bytes(Data)
        case pixelBuffer(DecodedPixelBuffer)
    }

    private final class DecodedPixelBuffer: @unchecked Sendable {
        let value: CVPixelBuffer

        init(_ value: CVPixelBuffer) {
            self.value = value
        }
    }

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

        let environment = ProcessInfo.processInfo.environment
        let requestedBackend = A4KComputeBackend.resolve(from: environment)
        let preferredDecodeBackend = Self.resolveDecodeBackend(environment: environment)
        let neuralAssistEnabled = environment["A4K_ENABLE_NEURAL_ASSIST"] != "0"
        let neuralStatus = neuralAssistEnabled
            ? Self.neuralAssistStatus()
            : (hasNeuralEngine: false, warmupSucceeded: false)
        let inflightWorkers = Self.resolveInflightWorkers(
            environment: environment,
            backend: requestedBackend,
            neuralAssistEnabled: neuralAssistEnabled && neuralStatus.hasNeuralEngine
        )
        let pipelineQueueDepth = Self.resolvePipelineQueueDepth(
            environment: environment,
            workerCount: inflightWorkers
        )

        let processors: [Anime4KOfflineProcessor]
        do {
            processors = try (0..<inflightWorkers).map { _ in
                try Anime4KOfflineProcessor(
                    shaderFileNames: shaderFiles,
                    targetOutputScale: Float(effectiveScale),
                    metalSourceDirectoryPath: metalSourceDir,
                    computeBackend: requestedBackend
                )
            }
        } catch {
            job.state = .failed
            job.errorMessage = error.localizedDescription
            return
        }

        guard let leadProcessor = processors.first else {
            job.state = .failed
            job.errorMessage = "Failed to initialize processing workers."
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
        if preferredDecodeBackend == .ffmpeg {
            job.appendLog("$ ffmpeg \(decodeArguments.joined(separator: " "))")
        } else {
            job.appendLog("[decode] preferred_backend=\(preferredDecodeBackend.logTag)")
        }
        job.appendLog("$ ffmpeg \(encodeArguments.joined(separator: " "))")
        job.appendLog("[backend] requested=\(leadProcessor.requestedBackend.rawValue) active=\(leadProcessor.activeBackend.rawValue)")
        job.appendLog("[pipeline] inflight_workers=\(inflightWorkers) queue_depth=\(pipelineQueueDepth)")

        if neuralAssistEnabled {
            let engineStatus = neuralStatus.hasNeuralEngine ? "detected" : "not_detected"
            let warmupStatus = neuralStatus.warmupSucceeded ? "ok" : "skipped_or_failed"
            job.appendLog("[neural] engine=\(engineStatus) warmup=\(warmupStatus) worker_hint=\(Self.neuralWorkerHint)")
        }

        let capturedFFmpegURL = ffmpegURL
        let capturedDecodeArgs = decodeArguments
        let capturedEncodeArgs = encodeArguments
        let capturedEnvironment = FFmpegLocator.processEnvironment()
        let capturedPreferredDecodeBackend = preferredDecodeBackend
        let capturedInputURL = job.file.url
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
                var decodeProcessLaunched = false
                var activeDecodeBackend = capturedPreferredDecodeBackend
                var videoToolboxReader: VideoToolboxFrameReader?
                var decodeOutputHandle: FileHandle?
                var decodeErrHandle: FileHandle?

                if activeDecodeBackend == .videoToolbox {
                    do {
                        videoToolboxReader = try VideoToolboxFrameReader(inputURL: capturedInputURL)
                    } catch {
                        activeDecodeBackend = .ffmpeg
                        await MainActor.run {
                            job.appendLog("[decode] videotoolbox unavailable (\(error.localizedDescription)); falling back to ffmpeg")
                        }
                    }
                }

                if activeDecodeBackend == .ffmpeg {
                    decodeProcess.executableURL = capturedFFmpegURL
                    decodeProcess.arguments = capturedDecodeArgs
                    decodeProcess.environment = capturedEnvironment

                    let decodeOutPipe = Pipe()
                    let decodeErrPipe = Pipe()
                    decodeProcess.standardOutput = decodeOutPipe
                    decodeProcess.standardError = decodeErrPipe

                    decodeOutputHandle = decodeOutPipe.fileHandleForReading
                    decodeErrHandle = decodeErrPipe.fileHandleForReading
                }

                let encodeProcess = Process()
                encodeProcess.executableURL = capturedFFmpegURL
                encodeProcess.arguments = capturedEncodeArgs
                encodeProcess.environment = capturedEnvironment

                let encodeInPipe = Pipe()
                let encodeErrPipe = Pipe()
                encodeProcess.standardInput = encodeInPipe
                encodeProcess.standardError = encodeErrPipe

                let encodeErrHandle = encodeErrPipe.fileHandleForReading
                let encodeInputHandle = encodeInPipe.fileHandleForWriting

                func cleanupPipes() {
                    decodeErrHandle?.readabilityHandler = nil
                    encodeErrHandle.readabilityHandler = nil
                    try? decodeErrHandle?.close()
                    try? encodeErrHandle.close()
                    try? decodeOutputHandle?.close()
                    try? encodeInputHandle.close()
                    videoToolboxReader = nil
                }

                decodeErrHandle?.readabilityHandler = { handle in
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

                    if activeDecodeBackend == .ffmpeg {
                        try decodeProcess.run()
                        decodeProcessLaunched = true
                    }
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
                    self?.currentDecodeProcess = decodeProcessLaunched ? decodeProcess : nil
                    self?.currentEncodeProcess = encodeProcess
                    job.processHandle = encodeProcess
                    job.appendLog("[decode] active_backend=\(activeDecodeBackend.logTag)")
                }

                let inputFrameBytes = inputWidth * inputHeight * 4
                let outputFrameBytes = max(1, outputWidth * outputHeight * 4)
                let wallStart = Date()
                var lastUIUpdate = wallStart

                let workerCount = max(1, processors.count)
                let workerQueues = (0..<workerCount).map { workerIndex in
                    DispatchQueue(label: "a4k.export.worker.\(workerIndex)", qos: .userInitiated)
                }

                let writerQueue = DispatchQueue(label: "a4k.export.writer")
                let inflightSemaphore = DispatchSemaphore(value: max(workerCount, pipelineQueueDepth))
                let processingGroup = DispatchGroup()
                let stateLock = NSLock()

                var pendingOutputs: [Int: Data] = [:]
                var nextWriteIndex = 0
                var producedFrameCount = 0
                var encodedFrameCount = 0
                var processingError: String?

                func setProcessingErrorIfNeeded(_ message: String) {
                    stateLock.lock()
                    if processingError == nil {
                        processingError = message
                    }
                    stateLock.unlock()
                }

                func hasProcessingError() -> Bool {
                    stateLock.lock()
                    let hasError = processingError != nil
                    stateLock.unlock()
                    return hasError
                }

                while true {
                    let shouldCancel = await MainActor.run { [weak self] in
                        self?.cancellationRequested ?? true
                    }
                    if shouldCancel || hasProcessingError() {
                        break
                    }

                    inflightSemaphore.wait()

                    if hasProcessingError() {
                        inflightSemaphore.signal()
                        break
                    }

                    let decodedFrame: DecodedFrame?
                    do {
                        if activeDecodeBackend == .videoToolbox {
                            if let pixelBuffer = videoToolboxReader?.nextFrame() {
                                decodedFrame = .pixelBuffer(DecodedPixelBuffer(pixelBuffer))
                            } else {
                                decodedFrame = nil
                            }
                        } else {
                            guard let decodeOutputHandle else {
                                throw NSError(
                                    domain: "Anime4K.Decode",
                                    code: 1,
                                    userInfo: [NSLocalizedDescriptionKey: "Decoder output stream is unavailable"]
                                )
                            }

                            let frameData = try Self.readExactly(handle: decodeOutputHandle, byteCount: inputFrameBytes)
                            if let frameData, frameData.count != inputFrameBytes {
                                inflightSemaphore.signal()
                                setProcessingErrorIfNeeded("Truncated frame from decoder (got \(frameData.count), expected \(inputFrameBytes)).")
                                break
                            }
                            decodedFrame = frameData.map { .bytes($0) }
                        }
                    } catch {
                        inflightSemaphore.signal()
                        setProcessingErrorIfNeeded("Failed reading decoded frame stream: \(error.localizedDescription)")
                        break
                    }

                    guard let decodedFrame else {
                        inflightSemaphore.signal()
                        break
                    }

                    let frameOrdinal = producedFrameCount
                    producedFrameCount += 1
                    let workerIndex = frameOrdinal % workerCount

                    processingGroup.enter()
                    workerQueues[workerIndex].async {
                        defer {
                            inflightSemaphore.signal()
                            processingGroup.leave()
                        }

                        if hasProcessingError() {
                            return
                        }

                        var outputFrameData = Data(count: outputFrameBytes)

                        do {
                            let dims: (width: Int, height: Int)

                            switch decodedFrame {
                            case let .bytes(frameData):
                                dims = try processors[workerIndex].processFrame(
                                    inputFrame: frameData,
                                    inputWidth: inputWidth,
                                    inputHeight: inputHeight,
                                    nativeWidth: inputWidth,
                                    nativeHeight: inputHeight,
                                    targetOutputWidth: outputWidth,
                                    targetOutputHeight: outputHeight,
                                    outputFrame: &outputFrameData
                                )

                            case let .pixelBuffer(pixelBuffer):
                                dims = try processors[workerIndex].processPixelBuffer(
                                    pixelBuffer: pixelBuffer.value,
                                    nativeWidth: inputWidth,
                                    nativeHeight: inputHeight,
                                    targetOutputWidth: outputWidth,
                                    targetOutputHeight: outputHeight,
                                    outputFrame: &outputFrameData
                                )
                            }

                            if dims.width != outputWidth || dims.height != outputHeight {
                                setProcessingErrorIfNeeded(
                                    "Unexpected Metal output dimensions \(dims.width)x\(dims.height); expected \(outputWidth)x\(outputHeight)."
                                )
                                return
                            }
                        } catch {
                            setProcessingErrorIfNeeded("Metal frame processing failed: \(error.localizedDescription)")
                            return
                        }

                        writerQueue.sync {
                            if hasProcessingError() {
                                return
                            }

                            pendingOutputs[frameOrdinal] = outputFrameData

                            while let nextFrame = pendingOutputs.removeValue(forKey: nextWriteIndex) {
                                do {
                                    try encodeInputHandle.write(contentsOf: nextFrame)
                                } catch {
                                    setProcessingErrorIfNeeded("Failed writing encoded frame stream: \(error.localizedDescription)")
                                    return
                                }

                                encodedFrameCount += 1
                                nextWriteIndex += 1

                                let now = Date()
                                if now.timeIntervalSince(lastUIUpdate) >= throttleSeconds {
                                    let elapsed = max(now.timeIntervalSince(wallStart), 0.001)
                                    let processedSeconds = Double(encodedFrameCount) / fps
                                    let progress = totalDuration > 0 ? min(processedSeconds / totalDuration, 1.0) : 0.0
                                    let speed = processedSeconds / elapsed
                                    let realtimeFPS = Double(encodedFrameCount) / elapsed
                                    let ffmpegTime = Self.formatFFmpegTime(seconds: processedSeconds)
                                    lastUIUpdate = now

                                    Task { @MainActor in
                                        job.currentFrame = encodedFrameCount
                                        job.currentTime = ffmpegTime
                                        job.progress = progress
                                        job.speed = String(format: "%.2fx", speed)
                                        job.fps = String(format: "%.1f", realtimeFPS)
                                    }
                                }
                            }
                        }
                    }
                }

                processingGroup.wait()
                writerQueue.sync { }

                stateLock.lock()
                let finalProcessingError = processingError
                stateLock.unlock()

                try? encodeInputHandle.close()

                let cancelled = await MainActor.run { [weak self] in
                    self?.cancellationRequested ?? true
                }

                if cancelled || finalProcessingError != nil {
                    if decodeProcessLaunched && decodeProcess.isRunning {
                        decodeProcess.terminate()
                    }
                    if encodeProcess.isRunning { encodeProcess.terminate() }
                }

                if decodeProcessLaunched {
                    decodeProcess.waitUntilExit()
                }
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
                    } else if let finalProcessingError {
                        job.state = .failed
                        job.errorMessage = finalProcessingError
                        job.appendLog("[error] \(finalProcessingError)")
                    } else if (!decodeProcessLaunched || decodeProcess.terminationStatus == 0) && encodeProcess.terminationStatus == 0 {
                        job.state = .completed
                        job.progress = 1.0
                        job.appendLog("[done] processing completed successfully")
                    } else {
                        let decodeStatus = decodeProcessLaunched
                            ? String(decodeProcess.terminationStatus)
                            : activeDecodeBackend.logTag
                        let msg = "Pipeline exited with decode=\(decodeStatus), encode=\(encodeProcess.terminationStatus)"
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

    private static func resolveInflightWorkers(
        environment: [String: String],
        backend: A4KComputeBackend,
        neuralAssistEnabled: Bool
    ) -> Int {
        if let raw = environment["A4K_INFLIGHT_WORKERS"],
           let parsed = Int(raw) {
            return max(1, min(maxWorkerCount, parsed))
        }

        if let raw = environment["A4K_BENCH_WORKERS"],
           let parsed = Int(raw) {
            return max(1, min(maxWorkerCount, parsed))
        }

        let logicalCores = max(1, ProcessInfo.processInfo.activeProcessorCount)
        let baseWorkers = max(2, min(maxWorkerCount, logicalCores / 2))

        let backendAdjusted: Int
        switch backend {
        case .coreML:
            // Core ML stages can saturate ANE/GPU quickly; keep CPU fan-out modest.
            backendAdjusted = max(2, min(6, logicalCores / 3))
        case .mps:
            backendAdjusted = max(neuralWorkerHint, baseWorkers)
        case .metal:
            backendAdjusted = baseWorkers
        }

        if neuralAssistEnabled {
            return max(backendAdjusted, neuralWorkerHint)
        }
        return backendAdjusted
    }

    private static func resolvePipelineQueueDepth(
        environment: [String: String],
        workerCount: Int
    ) -> Int {
        if let raw = environment["A4K_PIPELINE_QUEUE_DEPTH"],
           let parsed = Int(raw) {
            return max(1, min(maxPipelineDepth, parsed))
        }

        // Keep decode and worker queues ahead enough to reduce idle bubbles.
        let autoDepth = workerCount + max(1, workerCount / 2)
        return max(workerCount, min(maxPipelineDepth, autoDepth))
    }

    private static func resolveDecodeBackend(environment: [String: String]) -> DecodeBackend {
        if let explicit = environment["A4K_DECODE_BACKEND"]?.lowercased() {
            switch explicit {
            case "videotoolbox", "vt", "video_toolbox":
                return .videoToolbox
            case "ffmpeg", "pipe":
                return .ffmpeg
            default:
                break
            }
        }

        if environment["A4K_USE_VT_DECODE"] == "1" {
            return .videoToolbox
        }

        return .ffmpeg
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

    private final class VideoToolboxFrameReader {
        enum ReaderError: LocalizedError {
            case noVideoTrack
            case cannotAddOutput
            case startFailed(String)

            var errorDescription: String? {
                switch self {
                case .noVideoTrack:
                    return "No video track found for VideoToolbox decode"
                case .cannotAddOutput:
                    return "Unable to configure VideoToolbox reader output"
                case let .startFailed(detail):
                    return "VideoToolbox decode start failed: \(detail)"
                }
            }
        }

        private let reader: AVAssetReader
        private let output: AVAssetReaderTrackOutput

        init(inputURL: URL) throws {
            let asset = AVURLAsset(url: inputURL)
            guard let track = asset.tracks(withMediaType: .video).first else {
                throw ReaderError.noVideoTrack
            }

            reader = try AVAssetReader(asset: asset)

            let outputSettings: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]

            output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
            output.alwaysCopiesSampleData = false

            guard reader.canAdd(output) else {
                throw ReaderError.cannotAddOutput
            }

            reader.add(output)

            guard reader.startReading() else {
                throw ReaderError.startFailed(reader.error?.localizedDescription ?? "unknown")
            }
        }

        func nextFrame() -> CVPixelBuffer? {
            guard reader.status == .reading,
                  let sampleBuffer = output.copyNextSampleBuffer(),
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                return nil
            }

            return pixelBuffer
        }
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
