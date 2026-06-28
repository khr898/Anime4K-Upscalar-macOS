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
    @ObservationIgnored private var userInitiatedCancel: Bool = false
    @ObservationIgnored private var activityToken: NSObjectProtocol?

    @ObservationIgnored private var lastStderrFlush: Date = .distantPast
    @ObservationIgnored private var lastStdoutFlush: Date = .distantPast
    @ObservationIgnored private var firstMetricWallDate: Date?
    @ObservationIgnored private var firstMetricMediaSeconds: Double?

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
        userInitiatedCancel = false

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
                    self?.resetPerformanceMetrics()
                    job.processHandle = process
                }

                // --- Stderr pipe handler ---
                stderrHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty,
                          let text = String(data: data, encoding: .utf8) else { return }

                    var logBatch: [String] = []
                    var lastProgress: FFmpegProgress?

                    for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                        let lineStr = String(line)
                        if let prog = FFmpegProgress.parse(line: lineStr) {
                            lastProgress = prog
                        } else {
                            logBatch.append(lineStr)
                        }
                    }

                    if lastProgress != nil || !logBatch.isEmpty {
                        let parsedProgress = lastProgress
                        let logs = logBatch
                        Task { @MainActor in
                            var frame: Int?
                            var time: String?
                            var fps: String?
                            var progress: Double?

                            if let prog = parsedProgress {
                                frame = prog.frame
                                time = prog.time
                                fps = String(format: "%.1f", prog.fps)
                                if capturedDuration > 0 {
                                    progress = min(prog.timeSeconds / capturedDuration, 1.0)
                                }
                            }

                            self?.handleStderrProgress(
                                frame: frame,
                                time: time,
                                fps: fps,
                                progress: progress,
                                logs: logs,
                                job: job
                            )
                        }
                    }
                }

                // --- Stdout pipe handler ---
                stdoutHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty,
                          let text = String(data: data, encoding: .utf8) else { return }

                    var lastUs: Double?
                    var lastMs: Double?
                    var lastFps: String?
                    var lastFrame: Int?

                    for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                        if line.hasPrefix("out_time_us=") {
                            lastUs = Double(line.dropFirst(12))
                        } else if line.hasPrefix("out_time_ms=") {
                            lastMs = Double(line.dropFirst(12))
                        } else if line.hasPrefix("fps=") {
                            lastFps = String(line.dropFirst(4))
                        } else if line.hasPrefix("frame=") {
                            if let f = Int(line.dropFirst(6)) { lastFrame = f }
                        }
                    }

                    if lastUs != nil || lastMs != nil || lastFps != nil || lastFrame != nil {
                        let us = lastUs
                        let ms = lastMs
                        let fps = lastFps
                        let frame = lastFrame
                        Task { @MainActor in
                            var progress: Double?
                            var mediaSeconds: Double?

                            if let us {
                                mediaSeconds = us / 1_000_000.0
                                if capturedDuration > 0 {
                                    progress = min(mediaSeconds! / capturedDuration, 1.0)
                                }
                            } else if let ms {
                                mediaSeconds = ms / 1_000_000.0
                                if capturedDuration > 0 {
                                    progress = min(mediaSeconds! / capturedDuration, 1.0)
                                }
                            }

                            self?.handleStdoutProgress(
                                progress: progress,
                                fps: fps,
                                frame: frame,
                                mediaSeconds: mediaSeconds,
                                job: job
                            )
                        }
                    }
                }

                // --- Termination handler ---
                process.terminationHandler = { [weak self] proc in
                    cleanupPipes()

                    Task { @MainActor [weak self] in
                        self?.resetPerformanceMetrics()

                        job.endDate = Date()
                        self?.currentProcess = nil
                        job.processHandle = nil

                        if proc.terminationStatus == 0 {
                            job.state = .completed
                            job.progress = 1.0
                            job.appendLog("✅ Processing completed successfully.")
                        } else if proc.terminationReason == .uncaughtSignal {
                            if self?.userInitiatedCancel == true {
                                job.state = .cancelled
                                job.appendLog("Processing cancelled by user.")
                            } else {
                                job.state = .failed
                                job.errorMessage = "ffmpeg terminated (signal \(proc.terminationStatus)). See log; verify bundled dependencies."
                                job.appendLog("ERROR: ffmpeg terminated by signal \(proc.terminationStatus).")
                            }
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
        userInitiatedCancel = true
        cancellationRequested = true
        if let process = currentProcess, process.isRunning {
            process.terminate()
        }
    }

    /// Cancel a specific job if it is currently running.
    func cancelJob(_ job: ProcessingJob) {
        userInitiatedCancel = true
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
            job.state = .failed; job.errorMessage = "Bundled ffmpeg missing."; return
        }
        guard let realesrganURL = FFmpegLocator.realesrganURL else {
            job.state = .failed; job.errorMessage = "realesrgan-ncnn-vulkan missing."; return
        }
        let modelsDir = FFmpegLocator.realesrganModelsDirectory

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("A4K_NSR_\(job.id.uuidString)")
        let framesDir = tempDir.appendingPathComponent("frames")
        let upscaledDir = tempDir.appendingPathComponent("upscaled")
        do {
            try FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: upscaledDir, withIntermediateDirectories: true)
        } catch { job.state = .failed; job.errorMessage = "Temp dir failed."; return }
        defer { try? FileManager.default.removeItem(at: tempDir) }

        job.state = .running; job.progress = 0.0; job.startDate = Date()

        // Stage 1: decode to PNG.
        job.appendLog("Stage 1/3: decoding to frames…")
        let decode = ["-y", "-progress", "pipe:1", "-i", job.file.url.path,
                      "-pix_fmt", "rgb24", framesDir.appendingPathComponent("%08d.png").path]
        guard await runSubprocess(executableURL: ffmpegURL, arguments: decode, job: job, step: 1),
              !cancellationRequested else { return }

        // Stage 2: ncnn upscale. Resolve name + valid scale for the vendored files.
        let target = job.configuration.resolution.scaleFactor
        let (mName, mScale) = Self.resolveNcnnModel(job.configuration.mode, target: target, modelsDir: modelsDir)
        job.appendLog("Stage 2/3: Real-ESRGAN (\(mName), x\(mScale))…")
        let up = ["-i", framesDir.path, "-o", upscaledDir.path,
                  "-n", mName, "-m", modelsDir, "-s", String(mScale),
                  "-j", "1:2:2", "-t", "256", "-f", "png"]
        guard await runSubprocess(executableURL: realesrganURL, arguments: up, job: job, step: 2,
                                  workingDirectory: URL(fileURLWithPath: modelsDir).deletingLastPathComponent()),
              !cancellationRequested else { return }

        // Stage 3: encode, resizing to the user's target if the model scale differs.
        let asset = AVURLAsset(url: job.file.url)
        let fps: Float = (try? await asset.loadTracks(withMediaType: .video).first?.load(.nominalFrameRate)) ?? 23.976
        let fpsStr = String(format: "%.3f", fps)
        var enc = ["-y", "-progress", "pipe:1", "-r", fpsStr,
                   "-i", upscaledDir.appendingPathComponent("%08d.png").path,
                   "-i", job.file.url.path,
                   "-map", "0:v:0", "-map", "1:a?", "-map", "1:s?",
                   "-c:a", "copy", "-c:s", "copy",
                   "-c:v", job.configuration.codec.encoderName,
                   "-pix_fmt", job.configuration.codec.pixelFormat]
        if mScale != target {
            enc += ["-vf", "scale=iw*\(target)/\(mScale):ih*\(target)/\(mScale):flags=lanczos"]
        }
        enc.append(job.outputURL!.path)
        job.appendLog("Stage 3/3: encoding…")
        if await runSubprocess(executableURL: ffmpegURL, arguments: enc, job: job, step: 3),
           !cancellationRequested {
            job.state = .completed; job.progress = 1.0; job.appendLog("Neural SR completed.")
        }
    }

    /// Picks a model name + scale that exist among the vendored files.
    nonisolated static func resolveNcnnModel(_ mode: Anime4KMode, target: Int, modelsDir: String) -> (String, Int) {
        let fm = FileManager.default
        func exists(_ n: String) -> Bool { fm.fileExists(atPath: "\(modelsDir)/\(n).param") }
        switch mode.modelName {
        case "realesr-animevideov3":
            let s = [2,3,4].contains(target) ? target : 4
            let explicit = "realesr-animevideov3-x\(s)"
            if exists(explicit) { return (explicit, s) }
            if exists("realesr-animevideov3") { return ("realesr-animevideov3", s) }
            return (explicit, s)
        case "realesrgan-x4plus-anime": return ("realesrgan-x4plus-anime", 4)
        case "realesrgan-x4plus":       return ("realesrgan-x4plus", 4)
        default:                        return ("realesr-animevideov3-x4", 4)
        }
    }

    private func runSubprocess(executableURL: URL, arguments: [String], job: ProcessingJob, step: Int, workingDirectory: URL? = nil) async -> Bool {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = FFmpegLocator.processEnvironment()
        if let wd = workingDirectory { process.currentDirectoryURL = wd }
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

        let targetScale = max(2, job.configuration.resolution.scaleFactor)   // upscaling modes never 1x
        let isSDRescue = (job.configuration.mode == .special_SDRescue)
        let modelName = job.configuration.mode.modelName ?? "realesr-animevideov3"

        // --- Optional SD-Rescue pre-pass (Anime4K Restore VL -> PNG frames) runs out-of-process. ---
        var denoisedFramesDir: URL?
        var tempRoot: URL?
        if isSDRescue {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("A4K_ANE_\(job.id.uuidString)")
            let frames = root.appendingPathComponent("denoised")
            do { try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true) }
            catch { job.state = .failed; job.errorMessage = "Temp dir failed."; return }
            tempRoot = root; denoisedFramesDir = frames

            guard let ffmpeg = FFmpegLocator.ffmpegURL else {
                job.state = .failed; job.errorMessage = "Bundled ffmpeg missing."; return
            }
            let shader = "\(FFmpegLocator.shaderDirectoryPath)/Anime4K_Restore_CNN_VL.glsl"
            let args = ["-init_hw_device", "vulkan=vk:0", "-filter_hw_device", "vk", "-y",
                        "-i", job.file.url.path,
                        "-vf", "hwupload,libplacebo=custom_shader_path=\(shader),hwdownload,format=rgb24",
                        frames.appendingPathComponent("%08d.png").path]
            job.appendLog("Stage 1/2: Anime4K Restore VL pre-pass…")
            let ok = await runSubprocess(executableURL: ffmpeg, arguments: args, job: job, step: 1)
            if !ok || cancellationRequested {
                try? FileManager.default.removeItem(at: root)
                if cancellationRequested { /* runSubprocess already set .cancelled */ }
                return
            }
        }
        defer { if let r = tempRoot { try? FileManager.default.removeItem(at: r) } }

        // --- Load model (compiles .mlpackage on first use). ---
        let upscaler: CoreMLUpscaler
        do { upscaler = try CoreMLUpscaler(modelName: modelName) }
        catch {
            job.state = .failed
            job.errorMessage = "Failed to load model \(modelName): \(error.localizedDescription)"
            job.appendLog("ERROR: \(job.errorMessage!)")
            return
        }

        // --- Gather source metadata. ---
        let asset = AVURLAsset(url: job.file.url)
        let (naturalSize, fps, duration): (CGSize, Double, Double)
        if let track = try? await asset.loadTracks(withMediaType: .video).first {
            naturalSize = (try? await track.load(.naturalSize)) ?? CGSize(width: 1920, height: 1080)
            fps = Double((try? await track.load(.nominalFrameRate)) ?? 23.976)
            duration = (try? await asset.load(.duration))?.seconds ?? (job.file.durationSeconds ?? 1.0)
        } else {
            naturalSize = CGSize(width: 1920, height: 1080); fps = 23.976; duration = job.file.durationSeconds ?? 1.0
        }
        let inW = Int(naturalSize.width), inH = Int(naturalSize.height)
        let outW = inW * targetScale, outH = inH * targetScale
        let totalFrames = max(1, Int(duration * fps))

        // Capture Sendable values; run the heavy loop OFF the main actor.
        let userCancelled: @Sendable () -> Bool = { [weak self] in self?.cancellationRequested ?? true }
        let denoisedDir = denoisedFramesDir
        let outputURL = job.outputURL!
        let codec = job.configuration.codec

        let result: CoreMLJobResult = await Task.detached(priority: .userInitiated) {
            await Self.runANEEncode(job: job, upscaler: upscaler, asset: asset,
                                    isSDRescue: isSDRescue, denoisedDir: denoisedDir,
                                    inW: inW, inH: inH, outW: outW, outH: outH, fps: fps,
                                    targetScale: targetScale, totalFrames: totalFrames,
                                    outputURL: outputURL, codec: codec, isCancelled: userCancelled)
        }.value

        switch result {
        case .completed:
            job.state = .completed; job.progress = 1.0; job.endDate = Date()
            job.appendLog("Core ML (ANE) processing completed.")
        case .cancelled:
            job.state = .cancelled; job.endDate = Date()
            job.appendLog("Processing cancelled by user.")
        case .failed(let msg):
            job.state = .failed; job.errorMessage = msg; job.endDate = Date()
            job.appendLog("ERROR: \(msg)")
        }
    }

    private enum CoreMLJobResult: Sendable { case completed, cancelled, failed(String) }

    /// Off-main-actor ANE encode loop. Reads frames (decoded source or denoised PNGs),
    /// upscales each via Core ML, writes them in order. Constant memory, back-pressured.
    nonisolated private static func runANEEncode(
        job: ProcessingJob, upscaler: CoreMLUpscaler, asset: AVURLAsset,
        isSDRescue: Bool, denoisedDir: URL?, inW: Int, inH: Int, outW: Int, outH: Int,
        fps: Double, targetScale: Int, totalFrames: Int, outputURL: URL,
        codec: VideoCodec, isCancelled: @escaping @Sendable () -> Bool
    ) async -> CoreMLJobResult {
        // Writer (HEVC into a temp .mov, then remux to the requested container/codec if needed).
        let needsRemux = (outputURL.pathExtension.lowercased() == "mkv") || (codec == .svtAV1)
        let writeURL = needsRemux
            ? FileManager.default.temporaryDirectory.appendingPathComponent("A4K_\(job.id.uuidString).mov")
            : outputURL
        try? FileManager.default.removeItem(at: writeURL)

        guard let writer = try? AVAssetWriter(outputURL: writeURL, fileType: .mov) else {
            return .failed("Failed to create writer.")
        }
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: outW, AVVideoHeightKey: outH,
            AVVideoCompressionPropertiesKey: [
                AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel,
                AVVideoAverageBitRateKey: Int(fps * Double(outW) * Double(outH) * 0.12)
            ]
        ]
        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: vInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: outW,
                kCVPixelBufferHeightKey as String: outH])
        guard writer.canAdd(vInput) else { return .failed("Cannot add video track.") }
        writer.add(vInput)

        // Reader for the decoded source (non-SD path) and for audio passthrough (both paths).
        guard let reader = try? AVAssetReader(asset: asset) else { return .failed("Failed to create reader.") }
        var videoOut: AVAssetReaderTrackOutput?
        if !isSDRescue, let vt = try? await asset.loadTracks(withMediaType: .video).first {
            let o = AVAssetReaderTrackOutput(track: vt,
                outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            if reader.canAdd(o) { reader.add(o); videoOut = o }
        }
        var audioOut: AVAssetReaderTrackOutput?
        var audioIn: AVAssetWriterInput?
        if let at = try? await asset.loadTracks(withMediaType: .audio).first {
            let o = AVAssetReaderTrackOutput(track: at, outputSettings: nil)
            if reader.canAdd(o) { reader.add(o); audioOut = o }
            let i = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
            if writer.canAdd(i) { writer.add(i); audioIn = i }
        }

        if videoOut != nil || audioOut != nil {
            guard reader.startReading() else { return .failed("Reader start failed: \(reader.error?.localizedDescription ?? "")") }
        }
        guard writer.startWriting() else { return .failed("Writer start failed: \(writer.error?.localizedDescription ?? "")") }
        writer.startSession(atSourceTime: .zero)

        let q = DispatchQueue(label: "a4k.ane.encode")
        var frameIndex = 0
        var sdFrame = 1
        let start = Date()

        func nextUpscaledFrame() -> (CVPixelBuffer, CMTime)? {
            if isSDRescue {
                guard let dir = denoisedDir else { return nil }
                let url = dir.appendingPathComponent(String(format: "%08d.png", sdFrame))
                guard FileManager.default.fileExists(atPath: url.path),
                      let ci = CIImage(contentsOf: url) else { return nil }
                sdFrame += 1
                let pts = CMTime(value: CMTimeValue(frameIndex), timescale: CMTimeScale(fps))
                if let up = try? upscaler.upscale(ci, width: inW, height: inH, targetScale: targetScale) {
                    return (up, pts)
                }
                return nil
            } else {
                guard let sb = videoOut?.copyNextSampleBuffer(),
                      let pb = CMSampleBufferGetImageBuffer(sb) else { return nil }
                let pts = CMSampleBufferGetPresentationTimeStamp(sb)
                if let up = try? upscaler.upscale(pb, targetScale: targetScale) { return (up, pts) }
                return nil
            }
        }

        // Drive video on a writer-ready callback (back-pressure, no busy-wait).
        let videoDone = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            vInput.requestMediaDataWhenReady(on: q) {
                while vInput.isReadyForMoreMediaData {
                    if isCancelled() { cont.resume(returning: false); return }
                    guard let (buf, pts) = nextUpscaledFrame() else {
                        vInput.markAsFinished(); cont.resume(returning: true); return
                    }
                    adaptor.append(buf, withPresentationTime: pts)
                    frameIndex += 1
                    if frameIndex % 10 == 0 {
                        let f = frameIndex
                        let elapsed = Date().timeIntervalSince(start)
                        let cur = Double(f) / max(elapsed, 0.001)
                        Task { @MainActor in
                            job.progress = min(0.99, Double(f) / Double(totalFrames))
                            job.currentFrame = f
                            job.fps = String(format: "%.1f", cur)
                            job.speed = String(format: "x%.3f", cur / fps)
                        }
                    }
                }
            }
        }
        if !videoDone { reader.cancelReading(); writer.cancelWriting(); return .cancelled }

        // Audio passthrough.
        if let aIn = audioIn, let aOut = audioOut {
            let adone = await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                aIn.requestMediaDataWhenReady(on: q) {
                    while aIn.isReadyForMoreMediaData {
                        if isCancelled() { aIn.markAsFinished(); cont.resume(); return }
                        if let sb = aOut.copyNextSampleBuffer() { aIn.append(sb) }
                        else { aIn.markAsFinished(); cont.resume(); return }
                    }
                }
            }
            _ = adone
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writer.finishWriting { cont.resume() }
        }
        guard writer.status == .completed else {
            return .failed("Writer failed: \(writer.error?.localizedDescription ?? "status \(writer.status.rawValue)")")
        }

        // Remux to requested container/codec if needed (out-of-process, copy or AV1 transcode).
        if needsRemux {
            guard let ffmpeg = await MainActor.run(body: { FFmpegLocator.ffmpegURL }) else {
                return .failed("ffmpeg missing for remux.")
            }
            var args = ["-y", "-i", writeURL.path, "-i", job.file.url.path,
                        "-map", "0:v:0", "-map", "1:a?", "-map", "1:s?"]
            if codec == .svtAV1 {
                args += ["-c:v", "libsvtav1", "-pix_fmt", "yuv420p10le", "-crf", "30", "-preset", "6"]
            } else {
                args += ["-c:v", "copy"]
            }
            args += ["-c:a", "copy", "-c:s", "copy", outputURL.path]
            let proc = Process()
            proc.executableURL = ffmpeg
            proc.arguments = args
            proc.environment = await MainActor.run(body: { FFmpegLocator.processEnvironment() })
            do { try proc.run(); proc.waitUntilExit() }
            catch { return .failed("Remux launch failed: \(error.localizedDescription)") }
            try? FileManager.default.removeItem(at: writeURL)
            if proc.terminationStatus != 0 { return .failed("Remux exited \(proc.terminationStatus).") }
        }
        return .completed
    }

    // MARK: - Progress Updates (MainActor-Isolated)

    /// Helper to process stderr progress and log lines from FFmpeg
    private func handleStderrProgress(
        frame: Int?,
        time: String?,
        fps: String?,
        progress: Double?,
        logs: [String],
        force: Bool = false,
        job: ProcessingJob
    ) {
        let now = Date()
        let shouldFlush = force || now.timeIntervalSince(lastStderrFlush) >= Double(Self.uiUpdateIntervalMs) / 1000.0

        if shouldFlush {
            lastStderrFlush = now
            if let frame { job.currentFrame = frame }
            if let time { job.currentTime = time }
            if let fps { job.fps = fps }
            if let progress { job.progress = progress }
        }

        for log in logs {
            job.appendLog(log)
        }
    }

    /// Helper to process stdout progress from FFmpeg
    private func handleStdoutProgress(
        progress: Double?,
        fps: String?,
        frame: Int?,
        mediaSeconds: Double?,
        force: Bool = false,
        job: ProcessingJob
    ) {
        let now = Date()
        let shouldFlush = force || now.timeIntervalSince(lastStdoutFlush) >= Double(Self.uiUpdateIntervalMs) / 1000.0

        if shouldFlush {
            lastStdoutFlush = now
            if let progress { job.progress = progress }
            if let fps { job.fps = fps }
            if let frame { job.currentFrame = frame }

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

    /// Helper to reset performance metrics for a new job
    private func resetPerformanceMetrics() {
        lastStderrFlush = .distantPast
        lastStdoutFlush = .distantPast
        firstMetricWallDate = nil
        firstMetricMediaSeconds = nil
    }
}
