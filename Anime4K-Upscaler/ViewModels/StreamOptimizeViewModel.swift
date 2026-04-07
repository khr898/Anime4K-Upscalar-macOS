// Anime4K-Upscaler/ViewModels/StreamOptimizeViewModel.swift
// ViewModel for the Stream Optimize feature — directory management, file scanning, processing engine.

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import Observation
import IOKit.pwr_mgt

/// Central ViewModel for the Stream Optimize feature.
/// Manages source/destination directories, scans for video files,
/// and processes them with configurable streaming-optimized transcoding.
@MainActor @Observable
final class StreamOptimizeViewModel {

    // MARK: - Directory State

    var sourceDirectoryURL: URL?
    var destinationDirectoryURL: URL?

    var sourceDisplayName: String {
        sourceDirectoryURL?.lastPathComponent ?? "Not selected"
    }

    var destinationDisplayName: String {
        destinationDirectoryURL?.lastPathComponent ?? "Not selected"
    }

    // MARK: - Configuration State (defaults optimized for streaming delivery)

    var encoder: StreamEncoder = .hevcVideoToolbox {
        didSet { onEncoderChanged(from: oldValue) }
    }
    var quality: Int = 65
    var profile: StreamProfile = .main10
    var pixelFormat: StreamPixelFormat = .p010le
    var audioMode: StreamAudioMode = .copy
    var subtitleMode: StreamSubtitleMode = .movText
    var keyframeInterval: KeyframeInterval = .twoSeconds
    var faststart: Bool = true
    var allowSWFallback: Bool = true

    /// Builds a `StreamOptimizeConfiguration` snapshot from the current UI state.
    var currentConfiguration: StreamOptimizeConfiguration {
        StreamOptimizeConfiguration(
            encoder: encoder,
            quality: quality,
            profile: profile,
            pixelFormat: pixelFormat,
            audioMode: audioMode,
            subtitleMode: subtitleMode,
            keyframeInterval: keyframeInterval,
            faststart: faststart,
            allowSWFallback: allowSWFallback
        )
    }

    /// Reset profile, pixel format, and quality when encoder changes.
    private func onEncoderChanged(from old: StreamEncoder) {
        guard old != encoder else { return }
        quality = encoder.defaultQuality
        profile = encoder.defaultProfile
        pixelFormat = encoder.defaultPixelFormat
    }

    /// Restore all configuration to defaults.
    func resetToDefaults() {
        let d = StreamOptimizeConfiguration.default
        encoder = d.encoder
        quality = d.quality
        profile = d.profile
        pixelFormat = d.pixelFormat
        audioMode = d.audioMode
        subtitleMode = d.subtitleMode
        keyframeInterval = d.keyframeInterval
        faststart = d.faststart
        allowSWFallback = d.allowSWFallback
    }

    // MARK: - Scanned Files

    var files: [VideoFile] = []

    // MARK: - Processing State

    var viewState: ViewState = .configuration
    var isProcessing: Bool = false
    var currentJobIndex: Int = 0
    var totalJobs: Int = 0
    var overallProgress: Double = 0.0
    var jobs: [StreamOptimizeJob] = []

    enum ViewState: String {
        case configuration
        case processing
    }

    // MARK: - Internal Engine State

    @ObservationIgnored private var currentProcess: Process?
    @ObservationIgnored private var powerAssertionID: IOPMAssertionID = 0
    @ObservationIgnored private var hasPowerAssertion: Bool = false
    @ObservationIgnored private var cancellationRequested: Bool = false
    @ObservationIgnored private var activityToken: NSObjectProtocol?

    private static let uiUpdateIntervalMs: Int = 100

    /// Supported extensions for stream optimization (matching the shell function).
    private static let supportedExtensions: Set<String> = ["mkv", "mp4", "webm"]

    // MARK: - Directory Management

    func selectSourceDirectory() {
        if let url = SecurityScopeManager.shared.presentOutputDirectoryPicker() {
            sourceDirectoryURL = url
            scanSourceDirectory()
        }
    }

    func selectDestinationDirectory() {
        if let url = SecurityScopeManager.shared.presentOutputDirectoryPicker() {
            destinationDirectoryURL = url
        }
    }

    // MARK: - File Scanning

    /// Scans the source directory for video files on a background thread.
    /// FileManager enumeration is moved off MainActor to prevent UI blocking
    /// on directories with many files or slow volumes.
    func scanSourceDirectory() {
        guard let sourceURL = sourceDirectoryURL else {
            files = []
            return
        }

        SecurityScopeManager.shared.startAccessing(sourceURL)

        let supportedExts = Self.supportedExtensions
        Task.detached(priority: .userInitiated) { [weak self] in
            let fm = FileManager.default
            var scanned: [VideoFile] = []

            do {
                let contents = try fm.contentsOfDirectory(
                    at: sourceURL,
                    includingPropertiesForKeys: [.fileSizeKey],
                    options: [.skipsHiddenFiles]
                )

                for url in contents {
                    let ext = url.pathExtension.lowercased()
                    guard supportedExts.contains(ext) else { continue }
                    scanned.append(VideoFile(url: url))
                }

                // Sort by filename
                scanned.sort { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
            } catch {
                // Silently fail — files will be empty
            }

            await MainActor.run { [weak self] in
                self?.files = scanned
                self?.probeFiles()
            }
        }
    }

    private func probeFiles() {
        let unprobed = files.filter { $0.durationSeconds == nil }
        guard !unprobed.isEmpty else { return }
        let urls = unprobed.map(\.url)

        Task {
            let results = await DurationProbe.batchProbe(urls: urls)
            for (url, result) in results {
                if let index = files.firstIndex(where: { $0.url == url }),
                   let probeResult = result {
                    files[index].durationSeconds = probeResult.durationSeconds
                    files[index].width = probeResult.width
                    files[index].height = probeResult.height
                }
            }
        }
    }

    // MARK: - Computed Properties

    var canStartProcessing: Bool {
        !files.isEmpty && !isProcessing && destinationDirectoryURL != nil
    }

    var totalFileSize: String {
        let total = files.reduce(Int64(0)) { $0 + $1.fileSizeBytes }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    var totalDuration: String? {
        let durations = files.compactMap(\.durationSeconds)
        guard !durations.isEmpty else { return nil }
        let total = durations.reduce(0, +)
        let hours = Int(total) / 3600
        let minutes = (Int(total) % 3600) / 60
        let seconds = Int(total) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    var completedJobCount: Int {
        jobs.filter { $0.state == .completed }.count
    }

    var failedJobCount: Int {
        jobs.filter { $0.state == .failed }.count
    }

    var allJobsFinished: Bool {
        !jobs.isEmpty && jobs.allSatisfy { $0.state.isTerminal }
    }

    // MARK: - Processing Control

    func startProcessing() {
        guard canStartProcessing, let destURL = destinationDirectoryURL else { return }

        let config = currentConfiguration
        jobs = files.map { file in
            StreamOptimizeJob(file: file, configuration: config, destinationDirectory: destURL)
        }

        viewState = .processing

        Task {
            await executeBatch(jobs: jobs)
        }
    }

    func cancelProcessing() {
        cancellationRequested = true
        if let process = currentProcess, process.isRunning {
            process.terminate()
        }
    }

    func returnToConfiguration() {
        guard !isProcessing else { return }
        viewState = .configuration
    }

    // MARK: - Batch Execution

    private func executeBatch(jobs: [StreamOptimizeJob]) async {
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
            overallProgress = Double(index + 1) / Double(jobs.count)
        }

        endAppNapPrevention()
        releasePowerAssertion()
        isProcessing = false
    }

    // MARK: - Single Job Execution

    private func executeJob(_ job: StreamOptimizeJob) async {
        guard let ffmpegURL = FFmpegLocator.ffmpegURL,
              FileManager.default.isExecutableFile(atPath: ffmpegURL.path) else {
            job.state = .failed
            job.errorMessage = "FFmpeg binary not found in app bundle."
            return
        }

        guard let outputURL = job.outputURL else {
            job.state = .failed
            job.errorMessage = "Output URL could not be determined."
            return
        }

        let arguments = StreamOptimizeArgumentBuilder.build(
            inputURL: job.file.url,
            outputURL: outputURL,
            configuration: job.configuration
        )

        let totalDuration = job.file.durationSeconds ?? 0

        job.state = .running
        job.progress = 0.0
        job.startDate = Date()
        job.appendLog("$ ffmpeg \(arguments.joined(separator: " "))")

        let capturedFFmpegURL = ffmpegURL
        let capturedArguments = arguments
        let capturedEnvironment = FFmpegLocator.processEnvironment()
        let capturedDuration = totalDuration
        let throttleMs = Self.uiUpdateIntervalMs

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
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

                let stderrPipe = Pipe()
                let stdoutPipe = Pipe()
                process.standardError = stderrPipe
                process.standardOutput = stdoutPipe

                let stderrHandle = stderrPipe.fileHandleForReading
                let stdoutHandle = stdoutPipe.fileHandleForReading

                func cleanupPipes() {
                    stderrHandle.readabilityHandler = nil
                    stdoutHandle.readabilityHandler = nil
                    try? stderrHandle.close()
                    try? stdoutHandle.close()
                }

                await MainActor.run { [weak self] in
                    self?.currentProcess = process
                    job.processHandle = process
                }

                // Throttled stderr parsing
                nonisolated(unsafe) var lastFlush = ContinuousClock.now
                nonisolated(unsafe) var pendFrame: Int?
                nonisolated(unsafe) var pendTime: String?
                nonisolated(unsafe) var pendProcessedSeconds: Double?
                nonisolated(unsafe) var pendProgress: Double?
                nonisolated(unsafe) var firstMetricWallDate: Date?
                nonisolated(unsafe) var firstMetricTimeSeconds: Double?

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
                            pendProcessedSeconds = prog.timeSeconds
                            if capturedDuration > 0 {
                                pendProgress = min(prog.timeSeconds / capturedDuration, 1.0)
                            }
                        } else {
                            logBatch.append(lineStr)
                        }
                    }

                    let now = ContinuousClock.now
                    if (now - lastFlush) >= .milliseconds(throttleMs) || !logBatch.isEmpty {
                        let fr = pendFrame
                        let ti = pendTime
                        let ps = pendProcessedSeconds
                        let pr = pendProgress
                        let lg = logBatch
                        pendFrame = nil
                        pendTime = nil
                        pendProcessedSeconds = nil
                        pendProgress = nil
                        lastFlush = now

                        Task { @MainActor in
                            if let v = fr { job.currentFrame = v }
                            if let v = ti { job.currentTime = v }
                            if let processedSeconds = ps {
                                if firstMetricWallDate == nil && processedSeconds > 0 {
                                    firstMetricWallDate = Date()
                                    firstMetricTimeSeconds = processedSeconds
                                }

                                if let startWall = firstMetricWallDate,
                                   let startProcessed = firstMetricTimeSeconds {
                                    let elapsed = max(Date().timeIntervalSince(startWall), 0.001)
                                    let mediaDelta = max(processedSeconds - startProcessed, 0.0)

                                    if elapsed >= 0.35, mediaDelta > 0 {
                                        let speed = mediaDelta / elapsed
                                        let fps = Double(job.currentFrame) / elapsed
                                        job.speed = String(format: "x%.3f", speed)
                                        job.fps = String(format: "%.1f", fps)
                                    } else {
                                        job.speed = "warming..."
                                    }
                                }
                            }
                            if let v = pr { job.progress = v }
                            for l in lg { job.appendLog(l) }
                        }
                    }
                }

                stdoutHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                }

                process.terminationHandler = { [weak self] proc in
                    cleanupPipes()

                    let fFrame = pendFrame
                    let fProg = pendProgress

                    Task { @MainActor [weak self] in
                        if let v = fFrame { job.currentFrame = v }
                        if let v = fProg { job.progress = v }

                        job.endDate = Date()
                        self?.currentProcess = nil
                        job.processHandle = nil

                        if proc.terminationStatus == 0 {
                            job.state = .completed
                            job.progress = 1.0
                            job.appendLog("✅ Stream optimization completed successfully.")
                        } else if proc.terminationReason == .uncaughtSignal {
                            job.state = .cancelled
                            job.appendLog("🛑 Stream optimization cancelled by user.")
                        } else {
                            job.state = .failed
                            job.errorMessage = "FFmpeg exited with code \(proc.terminationStatus)"
                            job.appendLog("❌ FFmpeg exited with code \(proc.terminationStatus)")
                        }

                        safeResume()
                    }
                }

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

    // MARK: - Power Assertion

    private func acquirePowerAssertion() {
        guard !hasPowerAssertion else { return }
        let reason = "Anime4K Upscaler — Stream Optimize is processing video" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &powerAssertionID
        )
        hasPowerAssertion = (result == kIOReturnSuccess)
    }

    private func releasePowerAssertion() {
        guard hasPowerAssertion else { return }
        IOPMAssertionRelease(powerAssertionID)
        hasPowerAssertion = false
        powerAssertionID = 0
    }

    private func beginAppNapPrevention() {
        guard activityToken == nil else { return }
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Stream optimization in progress"
        )
    }

    private func endAppNapPrevention() {
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
    }
}
