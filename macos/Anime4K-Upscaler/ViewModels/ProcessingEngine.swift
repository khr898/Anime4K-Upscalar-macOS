// Anime4K-Upscaler/ViewModels/ProcessingEngine.swift
// Manages FFmpeg process lifecycle, progress parsing, and power assertion.

import Foundation
import IOKit.pwr_mgt
import Observation
import AVFoundation
import CoreML
import VideoToolbox
import CoreImage

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

    @ObservationIgnored private var currentProcess: Process?
    @ObservationIgnored private var powerAssertionID: IOPMAssertionID = 0
    @ObservationIgnored private var hasPowerAssertion: Bool = false
    @ObservationIgnored private var cancellationRequested: Bool = false
    @ObservationIgnored private var activityToken: NSObjectProtocol?

    /// Minimum interval between UI updates from pipe handlers.
    private static let uiUpdateIntervalMs: Int = 100 // 10 Hz cap

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
        if job.configuration.mode.isNeuralSR {
            await executeSubprocessNeuralJob(job)
            return
        }
        if job.configuration.mode.isSpecial {
            await executeCoreMLJob(job)
            return
        }

        guard let ffmpegURL = FFmpegLocator.ffmpegURL else {
            job.state = .failed
            job.errorMessage = "FFmpeg binary not found in app bundle."
            return
        }

        guard FileManager.default.isExecutableFile(atPath: ffmpegURL.path) else {
            job.state = .failed
            job.errorMessage = "FFmpeg binary is not executable."
            return
        }

        let shaderDir = FFmpegLocator.shaderDirectoryPath
        guard !shaderDir.isEmpty else {
            job.state = .failed
            job.errorMessage = "Shader directory not found in app bundle."
            return
        }

        guard let outputURL = job.outputURL else {
            job.state = .failed
            job.errorMessage = "Output URL could not be determined."
            return
        }

        let arguments = FFmpegArgumentBuilder.build(
            inputURL: job.file.url,
            outputURL: outputURL,
            configuration: job.configuration,
            shaderDirectory: shaderDir
        )

        // Probe duration for progress calculation
        let totalDuration = job.file.durationSeconds ?? 0

        job.state = .running
        job.progress = 0.0
        job.startDate = Date()
        job.appendLog("$ ffmpeg \(arguments.joined(separator: " "))")

        // Capture immutable values for Sendable context before entering detached task
        let capturedFFmpegURL = ffmpegURL
        let capturedArguments = arguments
        let capturedEnvironment = FFmpegLocator.processEnvironment()
        let capturedDuration = totalDuration
        let throttleMs = Self.uiUpdateIntervalMs

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // Guard against double-resume (terminationHandler + catch both call)
            nonisolated(unsafe) var didResume = false
            func safeResume() {
                guard !didResume else { return }
                didResume = true
                continuation.resume()
            }

            Task.detached(priority: .userInitiated) { [weak self] in
                let process = Process()
                process.executableURL = capturedFFmpegURL
                process.arguments = capturedArguments
                process.environment = capturedEnvironment
                process.qualityOfService = .userInitiated

                let stderrPipe = Pipe()
                let stdoutPipe = Pipe()
                process.standardError = stderrPipe
                process.standardOutput = stdoutPipe

                let stderrHandle = stderrPipe.fileHandleForReading
                let stdoutHandle = stdoutPipe.fileHandleForReading

                // Deterministic cleanup — always nil handlers and close fds
                func cleanupPipes() {
                    stderrHandle.readabilityHandler = nil
                    stdoutHandle.readabilityHandler = nil
                    try? stderrHandle.close()
                    try? stdoutHandle.close()
                }

                // Store process handle for cancellation
                await MainActor.run { [weak self] in
                    self?.currentProcess = process
                    job.processHandle = process
                }

                // --- Throttled stderr state ---
                nonisolated(unsafe) var lastStderrFlush = ContinuousClock.now
                nonisolated(unsafe) var pendFrame: Int?
                nonisolated(unsafe) var pendTime: String?
                nonisolated(unsafe) var pendFps: String?
                nonisolated(unsafe) var pendProgress: Double?

                stderrHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty,
                          let text = String(data: data, encoding: .utf8) else { return }

                    var logBatch: [String] = []

                    for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                        let lineStr = String(line)
                        if let prog = FFmpegProgress.parse(line: lineStr) {
                            pendFrame = prog.frame
                            pendTime = prog.time
                            pendFps = String(format: "%.1f", prog.fps)
                            if capturedDuration > 0 {
                                pendProgress = min(prog.timeSeconds / capturedDuration, 1.0)
                            }
                        } else {
                            logBatch.append(lineStr)
                        }
                    }

                    let now = ContinuousClock.now
                    let shouldFlush = (now - lastStderrFlush) >= .milliseconds(throttleMs)

                    if shouldFlush || !logBatch.isEmpty {
                        let fr = pendFrame
                        let ti = pendTime
                        let fp = pendFps
                        let pr = pendProgress
                        let lg = logBatch
                        pendFrame = nil
                        pendTime = nil
                        pendFps = nil
                        pendProgress = nil
                        lastStderrFlush = now

                        Task { @MainActor in
                            if let v = fr { job.currentFrame = v }
                            if let v = ti { job.currentTime = v }
                            if let v = fp { job.fps = v }
                            if let v = pr { job.progress = v }
                            for l in lg { job.appendLog(l) }
                        }
                    }
                }

                // --- Throttled stdout state ---
                nonisolated(unsafe) var lastStdoutFlush = ContinuousClock.now
                nonisolated(unsafe) var soProgress: Double?
                nonisolated(unsafe) var soFps: String?
                nonisolated(unsafe) var soFrame: Int?
                nonisolated(unsafe) var soMediaSeconds: Double?
                nonisolated(unsafe) var firstMetricWallDate: Date?
                nonisolated(unsafe) var firstMetricMediaSeconds: Double?

                stdoutHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty,
                          let text = String(data: data, encoding: .utf8) else { return }

                    // Work directly on Substring from split — avoids one
                    // String heap allocation per line vs String(line).
                    // Use dropFirst(n) instead of split(separator:"=").last
                    // to eliminate per-line Array<Substring> allocation.
                    for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                        if line.hasPrefix("out_time_us=") {
                            if let us = Double(line.dropFirst(12)) {
                                let mediaSeconds = us / 1_000_000.0
                                soMediaSeconds = mediaSeconds
                                if capturedDuration > 0 {
                                    soProgress = min(mediaSeconds / capturedDuration, 1.0)
                                }
                            }
                        } else if line.hasPrefix("out_time_ms=") {
                            if let us = Double(line.dropFirst(12)) {
                                let mediaSeconds = us / 1_000_000.0
                                soMediaSeconds = mediaSeconds
                                if capturedDuration > 0 {
                                    soProgress = min(mediaSeconds / capturedDuration, 1.0)
                                }
                            }
                        } else if line.hasPrefix("fps=") {
                            soFps = String(line.dropFirst(4))
                        } else if line.hasPrefix("frame=") {
                            if let f = Int(line.dropFirst(6)) { soFrame = f }
                        }
                    }

                    let now = ContinuousClock.now
                    if (now - lastStdoutFlush) >= .milliseconds(throttleMs) {
                        let p = soProgress
                        let f = soFps
                        let fr = soFrame
                        let mediaSeconds = soMediaSeconds
                        soProgress = nil
                        soFps = nil
                        soFrame = nil
                        soMediaSeconds = nil
                        lastStdoutFlush = now

                        Task { @MainActor in
                            if let v = p { job.progress = v }
                            if let v = f { job.fps = v }
                            if let v = fr { job.currentFrame = v }

                            if let mediaSeconds {
                                if firstMetricWallDate == nil && mediaSeconds > 0 {
                                    firstMetricWallDate = Date()
                                    firstMetricMediaSeconds = mediaSeconds
                                }

                                if let startWall = firstMetricWallDate,
                                   let startMedia = firstMetricMediaSeconds {
                                    let elapsed = max(Date().timeIntervalSince(startWall), 0.001)
                                    let mediaDelta = max(mediaSeconds - startMedia, 0.0)

                                    if elapsed >= 0.35, mediaDelta > 0 {
                                        let speed = mediaDelta / elapsed
                                        job.speed = String(format: "x%.3f", speed)
                                    } else {
                                        job.speed = "warming..."
                                    }
                                }
                            }
                        }
                    }
                }

                // --- Termination handler ---
                process.terminationHandler = { [weak self] proc in
                    cleanupPipes()

                    // Flush any remaining pending values
                    let fFrame = pendFrame ?? soFrame
                    let fProg = pendProgress ?? soProgress
                    let fFps = pendFps ?? soFps

                    Task { @MainActor [weak self] in
                        if let v = fFrame { job.currentFrame = v }
                        if let v = fProg { job.progress = v }
                        if let v = fFps { job.fps = v }

                        job.endDate = Date()
                        self?.currentProcess = nil
                        job.processHandle = nil

                        if proc.terminationStatus == 0 {
                            job.state = .completed
                            job.progress = 1.0
                            job.appendLog("✅ Processing completed successfully.")
                        } else if proc.terminationReason == .uncaughtSignal {
                            job.state = .cancelled
                            job.appendLog("🛑 Processing cancelled by user.")
                        } else {
                            job.state = .failed
                            job.errorMessage = "FFmpeg exited with code \(proc.terminationStatus)"
                            job.appendLog("❌ FFmpeg exited with code \(proc.terminationStatus)")
                        }

                        safeResume()
                    }
                }

                // --- Launch ---
                do {
                    try process.run()
                } catch {
                    cleanupPipes()
                    Task { @MainActor in
                        job.state = .failed
                        job.errorMessage = "Failed to launch FFmpeg: \(error.localizedDescription)"
                        job.endDate = Date()
                        job.appendLog("❌ Failed to launch: \(error.localizedDescription)")
                        safeResume()
                    }
                }
            }
        }
    }

    // MARK: - Cancellation

    /// Cancel the currently running job and abort the batch.
    func cancelAll() {
        cancellationRequested = true
        if let process = currentProcess, process.isRunning {
            process.terminate()
        }
    }

    /// Cancel a specific job if it is currently running.
    func cancelJob(_ job: ProcessingJob) {
        if let process = job.processHandle, process.isRunning {
            process.terminate()
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

    // MARK: - Neural SR Subprocess Pipeline

    private func executeSubprocessNeuralJob(_ job: ProcessingJob) async {
        guard let ffmpegURL = FFmpegLocator.ffmpegURL else {
            job.state = .failed
            job.errorMessage = "FFmpeg binary not found in app bundle."
            return
        }
        
        guard let realesrganURL = Bundle.main.url(forResource: "realesrgan-ncnn-vulkan", withExtension: nil) else {
            job.state = .failed
            job.errorMessage = "realesrgan-ncnn-vulkan binary not found in app bundle."
            return
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("Anime4KUpscaler_temp_\(job.id.uuidString)")
        let framesDir = tempDir.appendingPathComponent("frames")
        let upscaledDir = tempDir.appendingPathComponent("upscaled")

        do {
            try FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: upscaledDir, withIntermediateDirectories: true)
        } catch {
            job.state = .failed
            job.errorMessage = "Failed to create temp directories: \(error.localizedDescription)"
            return
        }

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        job.state = .running
        job.progress = 0.0
        job.startDate = Date()

        job.appendLog("Starting Stage 1/3: Decoding video to frames...")
        let decodeArgs = ["-y", "-i", job.file.url.path, "-qscale:v", "1", framesDir.appendingPathComponent("%08d.png").path]
        let decodeSuccess = await runSubprocess(executableURL: ffmpegURL, arguments: decodeArgs, job: job, step: 1)
        if !decodeSuccess || cancellationRequested { return }

        job.appendLog("Starting Stage 2/3: Upscaling frames via Real-ESRGAN...")
        let modelName = job.configuration.mode.modelName ?? "realesr-animevideov3"
        let upscaleArgs = ["-i", framesDir.path, "-o", upscaledDir.path, "-n", modelName, "-s", "4", "-j", "1:2:2", "-t", "0"]
        let upscaleSuccess = await runSubprocess(executableURL: realesrganURL, arguments: upscaleArgs, job: job, step: 2)
        if !upscaleSuccess || cancellationRequested { return }

        job.appendLog("Starting Stage 3/3: Re-encoding upscaled frames to video...")
        let fpsString = "23.976"
        let outputURL = job.outputURL!
        let encodeArgs = [
            "-y", "-r", fpsString, "-i", upscaledDir.appendingPathComponent("%08d.png").path,
            "-i", job.file.url.path,
            "-map", "0:v:0", "-map", "1:a?", "-map", "1:s?",
            "-c:a", "copy", "-c:s", "copy",
            "-c:v", job.configuration.codec.encoderName,
            "-pix_fmt", job.configuration.codec.pixelFormat,
            outputURL.path
        ]
        let encodeSuccess = await runSubprocess(executableURL: ffmpegURL, arguments: encodeArgs, job: job, step: 3)
        
        if encodeSuccess && !cancellationRequested {
            job.state = .completed
            job.progress = 1.0
            job.appendLog("✅ Neural SR completed successfully.")
        }
    }

    private func runSubprocess(executableURL: URL, arguments: [String], job: ProcessingJob, step: Int) async -> Bool {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = FFmpegLocator.processEnvironment()
        process.qualityOfService = .userInitiated

        let stderrPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = stdoutPipe

        let stderrHandle = stderrPipe.fileHandleForReading

        self.currentProcess = process
        job.processHandle = process

        let totalDuration = job.file.durationSeconds ?? 0

        stderrHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let text = String(data: data, encoding: .utf8) else { return }

            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                let lineStr = String(line)
                if step == 2 {
                    if let range = lineStr.range(of: "%"),
                       let val = Double(lineStr[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)) {
                        let percent = val / 100.0
                        let prog = 0.15 + 0.70 * percent
                        Task { @MainActor in
                            job.progress = prog
                            job.fps = "realesr"
                        }
                    }
                } else {
                    if let prog = FFmpegProgress.parse(line: lineStr) {
                        let progSeconds = prog.timeSeconds
                        if totalDuration > 0 {
                            let ratio = progSeconds / totalDuration
                            let progVal: Double
                            if step == 1 {
                                progVal = 0.15 * min(ratio, 1.0)
                            } else {
                                progVal = 0.85 + 0.15 * min(ratio, 1.0)
                            }
                            Task { @MainActor in
                                job.progress = progVal
                                job.currentFrame = prog.frame
                                job.currentTime = prog.time
                                job.fps = String(format: "%.1f", prog.fps)
                            }
                        }
                    }
                }
            }
        }

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { proc in
                stderrHandle.readabilityHandler = nil
                try? stderrHandle.close()
                try? stdoutPipe.fileHandleForReading.close()

                Task { @MainActor in
                    self.currentProcess = nil
                    job.processHandle = nil

                    if proc.terminationStatus == 0 {
                        continuation.resume(returning: true)
                    } else {
                        job.state = .failed
                        job.errorMessage = "Subprocess exited with code \(proc.terminationStatus)"
                        continuation.resume(returning: false)
                    }
                }
            }

            do {
                try process.run()
            } catch {
                Task { @MainActor in
                    job.state = .failed
                    job.errorMessage = "Failed to run subprocess: \(error.localizedDescription)"
                    continuation.resume(returning: false)
                }
            }
        }
    }

    // MARK: - Core ML ANE Pipeline

    private func executeCoreMLJob(_ job: ProcessingJob) async {
        job.state = .running
        job.progress = 0.0
        job.startDate = Date()
        
        let isSDRescue = job.configuration.mode == .special_SDRescue
        var denoisedFramesDir: URL? = nil
        var tempRoot: URL? = nil
        
        if isSDRescue {
            tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("Anime4KUpscaler_temp_\(job.id.uuidString)")
            let framesDir = tempRoot!.appendingPathComponent("denoised_frames")
            denoisedFramesDir = framesDir
            
            do {
                try FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)
            } catch {
                job.state = .failed
                job.errorMessage = "Failed to create temp directory for denoised frames."
                return
            }
            
            job.appendLog("Starting Stage 1/2: Pre-processing with Anime4K Restore VL...")
            
            guard let ffmpegURL = FFmpegLocator.ffmpegURL else {
                job.state = .failed
                job.errorMessage = "FFmpeg binary not found in app bundle."
                return
            }
            
            let shaderPath = "\(FFmpegLocator.shaderDirectoryPath)/Anime4K_Restore_CNN_VL.glsl"
            let decodeArgs = [
                "-init_hw_device", "vulkan=vk:0",
                "-filter_hw_device", "vk",
                "-y",
                "-i", job.file.url.path,
                "-vf", "hwupload,libplacebo=custom_shader_path=\(shaderPath),hwdownload,format=rgb24",
                framesDir.appendingPathComponent("%08d.png").path
            ]
            
            let decodeSuccess = await runSubprocess(executableURL: ffmpegURL, arguments: decodeArgs, job: job, step: 1)
            if !decodeSuccess || cancellationRequested {
                try? FileManager.default.removeItem(at: tempRoot!)
                return
            }
        }
        
        defer {
            if let tempRoot = tempRoot {
                try? FileManager.default.removeItem(at: tempRoot)
            }
        }
        
        job.appendLog(isSDRescue ? "Starting Stage 2/2: Initializing Core ML pipeline on Neural Engine..." : "Starting Stage 2: Initializing Core ML pipeline on Neural Engine...")
        
        let modelName = job.configuration.mode.modelName ?? "realesr-animevideov3"
        job.appendLog("Loading model: \(modelName).mlmodelc (takes 1-4 seconds on first load)...")
        
        guard let upscaler = try? CoreMLUpscaler(modelName: modelName) else {
            job.state = .failed
            job.errorMessage = "Failed to load CoreML model: \(modelName).mlmodelc. Make sure you compile the model and place it in the app bundle."
            job.appendLog("❌ Error: \(job.errorMessage!)")
            return
        }

        // Setup AVAssetReader and AVAssetWriter
        let asset = AVAsset(url: job.file.url)
        
        let naturalSize: CGSize
        let nominalFrameRate: Float
        let totalDuration: Double
        
        if let videoTrack = try? await asset.loadTracks(withMediaType: .video).first {
            naturalSize = (try? await videoTrack.load(.naturalSize)) ?? CGSize(width: 1920, height: 1080)
            nominalFrameRate = (try? await videoTrack.load(.nominalFrameRate)) ?? 23.976
            totalDuration = (try? await asset.load(.duration))?.seconds ?? (job.file.durationSeconds ?? 1.0)
        } else {
            naturalSize = CGSize(width: 1920, height: 1080)
            nominalFrameRate = 23.976
            totalDuration = job.file.durationSeconds ?? 1.0
        }
        
        let width = Int(naturalSize.width)
        let height = Int(naturalSize.height)
        let fps = Double(nominalFrameRate)
        
        guard let reader = try? AVAssetReader(asset: asset) else {
            job.state = .failed
            job.errorMessage = "Failed to initialize AVAssetReader."
            job.appendLog("❌ Error: \(job.errorMessage!)")
            return
        }
        
        var readerOutput: AVAssetReaderTrackOutput?
        var hasReaderOutputs = false
        
        if !isSDRescue {
            if let videoTrack = try? await asset.loadTracks(withMediaType: .video).first {
                let outputSettings: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                let out = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
                if reader.canAdd(out) {
                    reader.add(out)
                    readerOutput = out
                    hasReaderOutputs = true
                }
            }
        }
        
        guard let writer = try? AVAssetWriter(outputURL: job.outputURL!, fileType: .mp4) else {
            job.state = .failed
            job.errorMessage = "Failed to initialize AVAssetWriter."
            job.appendLog("❌ Error: \(job.errorMessage!)")
            return
        }
        
        // Output settings for encoding
        let upscaleScale = 4
        let outputWidth = width * upscaleScale
        let outputHeight = height * upscaleScale
        
        let averageBitRate: Int
        switch job.configuration.compression {
        case .visuallyLossless:
            averageBitRate = Int(fps * Double(outputWidth) * Double(outputHeight) * 0.15)
        case .balanced:
            averageBitRate = Int(fps * Double(outputWidth) * Double(outputHeight) * 0.08)
        case .customQuality(let q):
            let factor = Double(q) / 100.0
            averageBitRate = Int(fps * Double(outputWidth) * Double(outputHeight) * 0.20 * factor)
        case .fixedBitrate(let mbps):
            averageBitRate = mbps * 1_000_000
        }
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: outputWidth,
            AVVideoHeightKey: outputHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: averageBitRate,
                AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel
            ]
        ]
        
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: outputWidth,
                kCVPixelBufferHeightKey as String: outputHeight
            ]
        )
        
        if writer.canAdd(writerInput) {
            writer.add(writerInput)
        } else {
            job.state = .failed
            job.errorMessage = "Failed to add video track input to writer."
            job.appendLog("❌ Error: \(job.errorMessage!)")
            return
        }
        
        // Optional Audio track copying
        var audioReaderOutput: AVAssetReaderTrackOutput?
        var audioWriterInput: AVAssetWriterInput?
        
        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first {
            let out = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            if reader.canAdd(out) {
                reader.add(out)
                audioReaderOutput = out
                hasReaderOutputs = true
            }
            
            let inp = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
            if writer.canAdd(inp) {
                writer.add(inp)
                audioWriterInput = inp
            }
        }
        
        if hasReaderOutputs {
            guard reader.startReading() else {
                job.state = .failed
                job.errorMessage = "Reader failed to start reading: \(reader.error?.localizedDescription ?? "unknown error")"
                job.appendLog("❌ Error: \(job.errorMessage!)")
                return
            }
        }
        
        guard writer.startWriting() else {
            job.state = .failed
            job.errorMessage = "Writer failed to start writing: \(writer.error?.localizedDescription ?? "unknown error")"
            job.appendLog("❌ Error: \(job.errorMessage!)")
            return
        }
        
        writer.startSession(atSourceTime: .zero)
        
        job.appendLog("Processing frames natively via Apple Neural Engine...")
        
        var frameCount = 0
        let totalFrames = Int(totalDuration * Double(fps))
        let startTime = Date()
        
        var videoFinished = false
        var audioFinished = audioWriterInput == nil
        
        while !videoFinished || !audioFinished {
            if cancellationRequested {
                if hasReaderOutputs { reader.cancelReading() }
                writer.cancelWriting()
                job.state = .cancelled
                job.appendLog("🛑 Processing cancelled by user.")
                return
            }
            
            // Try writing audio
            if !audioFinished, let audioInput = audioWriterInput, audioInput.isReadyForMoreMediaData {
                if hasReaderOutputs, let sampleBuffer = audioReaderOutput?.copyNextSampleBuffer() {
                    audioInput.append(sampleBuffer)
                } else {
                    audioInput.markAsFinished()
                    audioFinished = true
                }
            }
            
            // Try writing video
            if !videoFinished, writerInput.isReadyForMoreMediaData {
                if isSDRescue {
                    let frameIndex = frameCount + 1
                    let fileURL = denoisedFramesDir!.appendingPathComponent(String(format: "%08d.png", frameIndex))
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        if let ciImage = CIImage(contentsOf: fileURL) {
                            let presentationTime = CMTime(value: CMTimeValue(frameCount), timescale: CMTimeScale(fps))
                            
                            do {
                                let upscaledBuffer = try upscaler.upscaleFullFrameImage(ciImage, width: width, height: height)
                                pixelBufferAdaptor.append(upscaledBuffer, withPresentationTime: presentationTime)
                            } catch {
                                job.appendLog("⚠️ Upscaling failed at frame \(frameCount): \(error.localizedDescription)")
                            }
                            
                            frameCount += 1
                            let progress = totalFrames > 0 ? min(Double(frameCount) / Double(totalFrames), 0.99) : 0.5
                            let elapsed = Date().timeIntervalSince(startTime)
                            let currentFps = Double(frameCount) / max(elapsed, 0.001)
                            
                            if frameCount % 10 == 0 || frameCount == totalFrames {
                                let currentFrameCount = frameCount
                                let currentFpsStr = String(format: "%.1f", currentFps)
                                Task { @MainActor in
                                    job.progress = 0.15 + 0.85 * progress
                                    job.currentFrame = currentFrameCount
                                    job.fps = currentFpsStr
                                    job.speed = String(format: "x%.3f", currentFps / Double(fps))
                                }
                            }
                        } else {
                            job.appendLog("⚠️ Failed to load PNG frame at \(fileURL.path)")
                            frameCount += 1
                        }
                    } else {
                        writerInput.markAsFinished()
                        videoFinished = true
                    }
                } else {
                    if let sampleBuffer = readerOutput?.copyNextSampleBuffer() {
                        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                            
                            do {
                                let upscaledBuffer = try upscaler.upscaleFullFrame(pixelBuffer)
                                pixelBufferAdaptor.append(upscaledBuffer, withPresentationTime: presentationTime)
                            } catch {
                                job.appendLog("⚠️ Upscaling failed at frame \(frameCount): \(error.localizedDescription)")
                            }
                            
                            frameCount += 1
                            let progress = totalFrames > 0 ? min(Double(frameCount) / Double(totalFrames), 0.99) : 0.5
                            let elapsed = Date().timeIntervalSince(startTime)
                            let currentFps = Double(frameCount) / max(elapsed, 0.001)
                            
                            if frameCount % 10 == 0 || frameCount == totalFrames {
                                let currentFrameCount = frameCount
                                let currentFpsStr = String(format: "%.1f", currentFps)
                                Task { @MainActor in
                                    job.progress = progress
                                    job.currentFrame = currentFrameCount
                                    job.fps = currentFpsStr
                                    job.speed = String(format: "x%.3f", currentFps / Double(fps))
                                }
                            }
                        }
                    } else {
                        writerInput.markAsFinished()
                        videoFinished = true
                    }
                }
            }
            
            if (!videoFinished && !writerInput.isReadyForMoreMediaData) &&
               (!audioFinished && !(audioWriterInput?.isReadyForMoreMediaData ?? false)) {
                try? await Task.sleep(nanoseconds: 1_000_000) // 1ms sleep
            }
        }
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                continuation.resume()
            }
        }
        
        if (!hasReaderOutputs || reader.status == .completed) && writer.status == .completed {
            job.state = .completed
            job.progress = 1.0
            job.endDate = Date()
            job.appendLog("✅ Native Core ML ANE processing completed successfully.")
        } else {
            let readerStatusRaw = hasReaderOutputs ? reader.status.rawValue : 0
            job.state = .failed
            job.errorMessage = "Reader/Writer failed: reader status \(readerStatusRaw), writer status \(writer.status.rawValue)"
            job.appendLog("❌ Error: \(job.errorMessage!)")
        }
    }
}
