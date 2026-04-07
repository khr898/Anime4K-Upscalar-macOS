// Anime4K-Upscaler/ViewModels/ProcessingEngine.swift
// Manages FFmpeg process lifecycle, progress parsing, and power assertion.

import Foundation
import IOKit.pwr_mgt
import Observation

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
}
