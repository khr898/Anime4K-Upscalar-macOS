// Anime4K-Upscaler/ViewModels/ProcessingEngine.swift
// Manages FFmpeg process lifecycle, progress parsing, and power assertion.

import Foundation
import IOKit.pwr_mgt
import Observation
import AVFoundation
import CoreML
import VideoToolbox
import CoreImage


/// Thread-safe cancellation flag shared with detached pipeline work.
/// Needed because `cancellationRequested` is main-actor-isolated and can't be
/// read from `@Sendable` closures running off-actor.
final class CancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var _isCancelled = false
    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isCancelled
    }
    func cancel() { lock.lock(); _isCancelled = true; lock.unlock() }
    func reset() { lock.lock(); _isCancelled = false; lock.unlock() }
}

/// Common interface for frame upscalers so the encode loop
/// (`ProcessingEngine.runUpscaleEncode`) is shared by the CoreML/ANE path and
/// the MetalFX/GPU path. Both take a decoded BGRA CVPixelBuffer + targetScale
/// and return an upscaled BGRA CVPixelBuffer.
protocol FrameUpscaler {
    func upscale(_ inputBuffer: CVPixelBuffer, targetScale: Int) throws -> CVPixelBuffer
}
extension CoreMLUpscaler: FrameUpscaler {}
extension MetalFXUpscaler: FrameUpscaler {}

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
    @ObservationIgnored private let cancelToken = CancellationToken()
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
        if job.configuration.mode.isSpecial || job.configuration.mode.isMetalFX {
            await executeUpscaleJob(job)
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
        cancelToken.cancel()
        if let process = currentProcess, process.isRunning {
            process.terminate()
        }
    }

    /// Cancel a specific job if it is currently running.
    func cancelJob(_ job: ProcessingJob) {
        userInitiatedCancel = true
        cancelToken.cancel()
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
        // ponytail: defer before createDirectory so a creation-failure partial dir is also cleaned
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let framesDir = tempDir.appendingPathComponent("frames")
        let upscaledDir = tempDir.appendingPathComponent("upscaled")
        do {
            try FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: upscaledDir, withIntermediateDirectories: true)
        } catch { job.state = .failed; job.errorMessage = "Temp dir failed."; return }

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
        guard let outURL = job.outputURL else {
            job.state = .failed; job.errorMessage = "Output URL could not be determined."; return
        }
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
        enc.append(contentsOf: FFmpegArgumentBuilder.compressionArguments(for: job.configuration))
        enc.append(outURL.path)
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
                    } else {
                        // ponytail: surface non-progress stderr (ffmpeg/realesrgan errors)
                        let l = lineStr
                        Task { @MainActor in job.appendLog(l) }
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
                    } else {
                        // ponytail: surface non-progress stderr (ffmpeg errors)
                        let l = lineStr
                        Task { @MainActor in job.appendLog(l) }
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

    private func executeUpscaleJob(_ job: ProcessingJob) async {
        job.state = .running
        job.progress = 0.0
        job.startDate = Date()
        cancelToken.reset()   // per-job token; a cancelJob on a previous job must not cancel this one

        let mode = job.configuration.mode
        // Special-neural modes run a fixed-ratio CoreML model (4×/2× native);
        // force its native scale so a stale selector value can't trigger a
        // wasteful 4×-infer-then-downscale-to-2× path (the picker is locked in
        // the UI — this is the belt-and-braces guard). MetalFX honors the
        // selector (arbitrary spatial scale).
        let targetScale = mode.isSpecial ? mode.fixedScaleFactor
                                         : max(2, job.configuration.resolution.scaleFactor)
        let isSDRescue = (mode == .special_SDRescue)
        let isMetalFX = mode.isMetalFX
        // Restore VL (libplacebo via Vulkan/MoltenVK) reconstructs line art before
        // the upscaler — used by SDRescue and both MetalFX pipelines. MetalFX+Sharpen
        // additionally applies a contrast-gated unsharp-mask compute pass after the
        // GPU upscale for anime edge sharpen (flat areas untouched).
        let usesRestoreShader = isSDRescue || isMetalFX
        let modelName = mode.modelName ?? "realesr-animevideov3"

        // --- Source metadata (dims needed before launching the streamer). ---
        // AVAssetReader refuses Matroska (-11828 "Cannot Open") but AVURLAsset
        // track-metadata loading works on MKV — only sample-reading is blocked,
        // so naturalSize/fps/duration are safe to load here. The streaming reader
        // replaces both the old PNG prepass and the AVAssetReader video path.
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

        // --- Load upscaler: MetalFX (GPU) for special_MetalFX, else CoreML (ANE). ---
        let upscaler: any FrameUpscaler
        do {
            if isMetalFX {
                upscaler = try MetalFXUpscaler(applySharpen: mode == .special_MetalFX_Sharp)
            } else {
                upscaler = try CoreMLUpscaler(modelName: modelName)
            }
        } catch {
            job.state = .failed
            job.errorMessage = "Failed to load \(isMetalFX ? "MetalFX upscaler" : "model \(modelName)"): \(error.localizedDescription)"
            job.appendLog("ERROR: \(job.errorMessage!)")
            return
        }

        // --- Streaming decode: ffmpeg -> stdout rawvideo BGRA -> CVPixelBuffer. ---
        // Zero temp disk, no PNG codec, container-agnostic. SDRescue applies the
        // Anime4K Restore VL libplacebo shader in the filter chain; other modes
        // decode plain. Both emit `-pix_fmt bgra -f rawvideo pipe:1` consumed by
        // RawVideoFrameSource. bgra matches the pipeline's native 32BGRA, so no
        // swizzle. 10/12-bit sources truncate to 8-bit at -pix_fmt (same as the
        // prior PNG path; CoreML models are 8-bit RGB regardless) — no upscale
        // quality regression.
        guard let ffmpeg = FFmpegLocator.ffmpegURL else {
            job.state = .failed; job.errorMessage = "Bundled ffmpeg missing."; return
        }

        // --- Decode probe ladder: VideoToolbox hardware first, libdav1d software
        // fallback second, default decoder last. AV1 sources MUST use an override
        // — the native `av1` decoder is hardware-only and yields zero frames on
        // devices without a functioning AV1 hwaccel, which previously flowed to
        // the writer as a clean EOF and surfaced as a misleading "Remux exited
        // 183." The probe pulls one raw frame off-main; on success it pushes
        // that frame back so the encode loop never loses it, on 0-frame failure
        // it retries the next mode, and if every mode fails the real error is
        // surfaced instead of writing an empty .mov. libdav1d works on every Mac
        // (Intel / M1 / M2 / M3+), so AV1 sources decode even without VT AV1.
        let shaderPath = "\(FFmpegLocator.shaderDirectoryPath)/Anime4K_Restore_CNN_VL.glsl"
        let modes: [RawVideoFrameSource.DecodeMode] = usesRestoreShader
            ? [.default, .softwareDav1d]      // -hwaccel videotoolbox is not applied to the Vulkan hwupload chain
            : [.videoToolbox, .softwareDav1d, .default]
        func modeLabel(_ m: RawVideoFrameSource.DecodeMode) -> String {
            switch m {
            case .videoToolbox: return "VideoToolbox hardware"
            case .softwareDav1d: return "libdav1d software"
            case .default: return "default decoder"
            }
        }

        // Throttle ffmpeg stderr → job log. ffmpeg dumps all stream / sub-track
        // / metadata info at startup; the old per-line `Task { @MainActor in
        // job.appendLog(line) }` spawned dozens of MainActor tasks and lagged
        // the UI. One throttle per job, shared across probe modes, batches lines
        // on a 100ms timer.
        let logThrottle = LogThrottle(interval: 0.1) { msg in
            Task { @MainActor in job.appendLog(msg) }
        }
        defer { logThrottle.stop() }

        var source: RawVideoFrameSource?
        var decodeError: String?
        for mode in modes {
            let args = RawVideoFrameSource.streamArgs(mode: mode, inputPath: job.file.url.path,
                                                       usesRestoreShader: usesRestoreShader, shaderPath: shaderPath)
            let s = RawVideoFrameSource(executableURL: ffmpeg, arguments: args,
                                        width: inW, height: inH,
                                        environment: FFmpegLocator.processEnvironment())
            s.onLog = { line in logThrottle.append(line) }
            do { try s.start() } catch {
                decodeError = "Decode stream failed to start (\(modeLabel(mode))): \(error.localizedDescription)"
                continue
            }
            // Probe one frame off-main so a dead/blocked ffmpeg can't stall the
            // main actor. nil = EOF or failure — consult hasFailed after reaping.
            let probed = await Task.detached(priority: .userInitiated) { () -> Data? in
                s.nextRawFrame()
            }.value
            if let probed {
                s.pushFrame(probed)
                source = s
                job.appendLog("Stage 1/2: \(usesRestoreShader ? "Anime4K Restore VL + " : "")decode via \(modeLabel(mode))…")
                break
            }
            s.waitUntilExited()
            s.cancel()
            if s.hasFailed {
                decodeError = "Decode failed (\(modeLabel(mode))): ffmpeg exited \(s.terminationStatus.map(String.init) ?? "?")."
                continue
            }
            // exit 0 but 0 frames → genuinely empty source; no mode will help.
            decodeError = "Source produced no frames."
            break
        }

        guard let source else {
            job.state = .failed
            job.errorMessage = decodeError ?? "Decode produced no frames."
            job.appendLog("ERROR: \(job.errorMessage!)")
            return
        }

        // Capture Sendable values; run the heavy loop OFF the main actor.
        // Default is NOT cancelled — a deallocated engine must not report phantom user cancels.
        let userCancelled: @Sendable () -> Bool = { [cancelToken] in cancelToken.isCancelled }
        guard let outputURL = job.outputURL else {
            source.cancel()
            job.state = .failed; job.errorMessage = "Output URL could not be determined."; return
        }
        let codec = job.configuration.codec

        let result: CoreMLJobResult = await Task.detached(priority: .userInitiated) {
            await Self.runUpscaleEncode(job: job, upscaler: upscaler, asset: asset,
                                    source: source,
                                    outW: outW, outH: outH, fps: fps,
                                    targetScale: targetScale, totalFrames: totalFrames,
                                    outputURL: outputURL, codec: codec, isCancelled: userCancelled)
        }.value

        switch result {
        case .completed:
            job.state = .completed; job.progress = 1.0; job.endDate = Date()
            job.appendLog(isMetalFX ? "MetalFX (GPU) processing completed." : "Core ML (ANE) processing completed.")
        case .cancelled:
            job.state = .cancelled; job.endDate = Date()
            job.appendLog("Processing cancelled by user.")
        case .failed(let msg):
            job.state = .failed; job.errorMessage = msg; job.endDate = Date()
            job.appendLog("ERROR: \(msg)")
        }
    }

    private enum CoreMLJobResult: Sendable { case completed, cancelled, failed(String) }

    /// Build the 16×9 luma signature (BGRA G channel, byte offset 1) for a
    /// decoded frame so `FrameRedundancyCache` can decide dup-reuse without a
    /// full-frame Data copy. Reads only 144 pixels with `bytesPerRow` stride
    /// (handles row padding). Mirrors `FrameRedundancyCache.signature` but on a
    /// locked CVPixelBuffer. Returns nil if the buffer can't be locked.
    nonisolated private static func lumaSignature(_ pb: CVPixelBuffer, w: Int, h: Int) -> [UInt8]? {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let bpr = CVPixelBufferGetBytesPerRow(pb)
        let gW = FrameRedundancyCache.gridW, gH = FrameRedundancyCache.gridH
        let strideX = max(1, w / gW), strideY = max(1, h / gH)
        var sig = [UInt8](repeating: 0, count: FrameRedundancyCache.cellCount)
        let row = base.assumingMemoryBound(to: UInt8.self)
        for cy in 0..<gH {
            for cx in 0..<gW {
                let px = min(cx * strideX, w - 1), py = min(cy * strideY, h - 1)
                let off = py * bpr + px * 4 + 1   // G channel (luma proxy), BGRA
                sig[cy * gW + cx] = row[off]
            }
        }
        return sig
    }

    /// Off-main-actor upscale encode loop. Pulls decoded BGRA frames from the
    /// streaming `source` (ffmpeg stdout rawvideo), upscales each via the given
    /// `FrameUpscaler` (CoreML/ANE or MetalFX/GPU), writes them in order. Zero
    /// temp disk, constant memory, back-pressured by the pipe. `asset` is used
    /// only for audio passthrough (when not remuxing); video never comes from
    /// AVAssetReader, which refuses containers AVFoundation can't sample-read
    /// (e.g. Matroska, -11828).
    nonisolated private static func runUpscaleEncode(
        job: ProcessingJob, upscaler: any FrameUpscaler, asset: AVURLAsset,
        source: RawVideoFrameSource, outW: Int, outH: Int,
        fps: Double, targetScale: Int, totalFrames: Int, outputURL: URL,
        codec: VideoCodec, isCancelled: @escaping @Sendable () -> Bool
    ) async -> CoreMLJobResult {
        // Writer (HEVC into a temp .mov, then remux to the requested container/codec if needed).
        let needsRemux = (outputURL.pathExtension.lowercased() == "mkv") || (codec == .svtAV1)
        let writeURL = needsRemux
            ? FileManager.default.temporaryDirectory.appendingPathComponent("A4K_\(job.id.uuidString).mov")
            : outputURL
        try? FileManager.default.removeItem(at: writeURL)
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: writeURL, fileType: .mov)
        } catch {
            return .failed("Failed to create writer: \(error.localizedDescription) [\((error as NSError).domain) \((error as NSError).code)]")
        }
        let targetBitrate: Int
        if job.configuration.compression.isFixedBitrate {
            targetBitrate = job.configuration.compression.bitrateMbps * 1_000_000
        } else {
            let q = Double(job.configuration.compression.qualityValue(for: .hevcVideoToolbox))
            let factor = max(0.04, min(0.35, 0.12 * (q / 68.0)))
            targetBitrate = Int(fps * Double(outW) * Double(outH) * factor)
        }
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: outW, AVVideoHeightKey: outH,
            AVVideoCompressionPropertiesKey: [
                AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel,
                AVVideoAverageBitRateKey: targetBitrate
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

        // Reader: used ONLY for in-process audio passthrough, and only when we are
        // NOT remuxing (the remux pulls audio+subs from the original file via
        // ffmpeg, so the reader is redundant on the remux path). Video always
        // comes from the streaming source. If the reader can't be created (e.g.
        // source container AVFoundation refuses), degrade to the ffmpeg audio-copy
        // mux fallback after the video writer finishes — never a silent output.
        let reader: AVAssetReader?
        var audioOut: AVAssetReaderTrackOutput?
        var audioIn: AVAssetWriterInput?
        if !needsRemux {
            if let aTrack = try? await asset.loadTracks(withMediaType: .audio).first,
               let r = try? AVAssetReader(asset: asset) {
                let aOut = AVAssetReaderTrackOutput(track: aTrack, outputSettings: nil)
                let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
                aIn.expectsMediaDataInRealTime = false
                if r.canAdd(aOut) && writer.canAdd(aIn) {
                    r.add(aOut); writer.add(aIn)
                    audioOut = aOut; audioIn = aIn; reader = r
                } else {
                    reader = nil
                }
            } else {
                reader = nil
            }
        } else {
            reader = nil
        }

        // Start session
        guard writer.startWriting() else {
            return .failed("startWriting failed: \(writer.error?.localizedDescription ?? "unknown")")
        }
        writer.startSession(atSourceTime: .zero)
        reader?.startReading()

        // Core encoding loop
        let success = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let channel = FrameChannel<(CVPixelBuffer, CMTime)>(capacity: 8)
            let redundancy = FrameRedundancyCache(threshold: 0.9995)
            var lastUpscaled: CVPixelBuffer?

            // Upscaler worker Task
            Task.detached(priority: .userInitiated) {
                var frameIndex = 0
                while !isCancelled() {
                    guard let buf = source.nextFrame() else { break }   // EOF
                    let pts = CMTime(value: CMTimeValue(frameIndex), timescale: CMTimeScale(fps))
                    let sig = redundancy.computeSignature(of: buf)
                    let reuse = sig.map { redundancy.shouldReuse(signature: $0) } ?? false
                    var up: CVPixelBuffer
                    if reuse, let last = lastUpscaled {
                        up = last
                    } else {
                        do { up = try upscaler.upscale(buf, targetScale: targetScale) }
                        catch {
                            channel.close()
                            await MainActor.run { job.appendLog("Upscale error: \(error.localizedDescription)") }
                            break
                        }
                        if sig != nil { lastUpscaled = up }
                    }
                    frameIndex += 1
                    channel.push((up, pts))
                }
                channel.close()
            }

            // Writer loop on private queue
            let writerQueue = DispatchQueue(label: "com.anime4k.writer", qos: .userInitiated)
            var wroteFrames = 0
            vInput.requestMediaDataWhenReady(on: writerQueue) {
                while vInput.isReadyForMoreMediaData {
                    if isCancelled() { source.cancel(); channel.close(); cont.resume(returning: false); return }
                    guard let (buf, pts) = channel.pop() else {
                        vInput.markAsFinished()
                        cont.resume(returning: true)
                        return
                    }
                    adaptor.append(buf, withPresentationTime: pts)
                    wroteFrames += 1
                    if wroteFrames % 30 == 0 || wroteFrames == totalFrames {
                        let prog = totalFrames > 0 ? min(1.0, Double(wroteFrames) / Double(totalFrames)) : 0.0
                        Task { @MainActor in
                            job.progress = prog
                            job.currentFrame = wroteFrames
                        }
                    }
                }
            }
        }

        guard success else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: writeURL)
            return .cancelled
        }

        // Finish in-process audio track if wired
        if let aIn = audioIn, let aOut = audioOut {
            let adone: Void = await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                let aQueue = DispatchQueue(label: "com.anime4k.audioWriter", qos: .userInitiated)
                aIn.requestMediaDataWhenReady(on: aQueue) {
                    while aIn.isReadyForMoreMediaData {
                        if let sb = aOut.copyNextSampleBuffer() { aIn.append(sb) }
                        else { aIn.markAsFinished(); cont.resume(); return }
                    }
                }
            }
            _ = adone
        }

        // Finish writer
        let wrote = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            writer.finishWriting { cont.resume(returning: writer.status == .completed) }
        }
        guard wrote else {
            try? FileManager.default.removeItem(at: writeURL)
            return .failed("finishWriting failed: \(writer.error?.localizedDescription ?? "unknown")")
        }

        // Audio mux fallback if reader was bypassed on non-remux path
        if audioIn == nil && !needsRemux {
            guard let ffmpeg = await MainActor.run(body: { FFmpegLocator.ffmpegURL }) else {
                return .failed("ffmpeg missing for audio mux.")
            }
            let muxTmp = FileManager.default.temporaryDirectory.appendingPathComponent("A4K_mux_\(job.id.uuidString).mp4")
            try? FileManager.default.removeItem(at: muxTmp)
            let args = ["-y", "-i", writeURL.path, "-i", job.file.url.path,
                        "-map", "0:v:0", "-map", "1:a?", "-map", "1:s?",
                        "-c", "copy", muxTmp.path]
            let proc = Process()
            proc.executableURL = ffmpeg
            proc.arguments = args
            proc.environment = await MainActor.run(body: { FFmpegLocator.processEnvironment() })
            do { try proc.run(); proc.waitUntilExit() }
            catch { return .failed("Audio mux failed: \(error.localizedDescription)") }
            try? FileManager.default.removeItem(at: writeURL)
            if proc.terminationStatus != 0 { return .failed("Audio mux exited \(proc.terminationStatus).") }
            do {
                try? FileManager.default.removeItem(at: outputURL)
                try FileManager.default.moveItem(at: muxTmp, to: outputURL)
            } catch {
                try? FileManager.default.removeItem(at: muxTmp)
                return .failed("Audio mux replace failed: \(error.localizedDescription)")
            }
        }

        // Remux to requested container/codec if needed (out-of-process, copy or AV1 transcode).
        if needsRemux {
            guard let ffmpeg = await MainActor.run(body: { FFmpegLocator.ffmpegURL }) else {
                return .failed("ffmpeg missing for remux.")
            }
            var args = ["-y", "-i", writeURL.path, "-i", job.file.url.path,
                        "-map", "0:v:0", "-map", "1:a?", "-map", "1:s?"]
            if codec == .svtAV1 {
                let crfVal = job.configuration.compression.qualityValue(for: .svtAV1)
                args += ["-c:v", "libsvtav1", "-pix_fmt", "yuv420p10le", "-preset", "\(job.configuration.svtAV1Preset)", "-crf", "\(crfVal)", "-svtav1-params", "tune=0"]
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
