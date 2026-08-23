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

    var destinationDirectoryURL: URL?

    var destinationDisplayName: String {
        destinationDirectoryURL?.lastPathComponent ?? "Not selected"
    }

    var outputDirectoryURL: URL? {
        get { destinationDirectoryURL }
        set { destinationDirectoryURL = newValue }
    }

    var outputDirectoryDisplayName: String {
        destinationDisplayName
    }

    // MARK: - Configuration State (defaults optimized for streaming delivery)

    var encoder: StreamEncoder = .hevcVideoToolbox {
        didSet { onEncoderChanged(from: oldValue) }
    }
    var quality: Int = 65
    var svtAV1Preset: Int = 6
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
            svtAV1Preset: svtAV1Preset,
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
        svtAV1Preset = d.svtAV1Preset
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
    var selectedFileID: UUID?

    // MARK: - File Management
    // Mirrors CompressViewModel so the Stream Optimize sidebar behaves like the
    // Upscale/Compress tabs: add via picker or drag-and-drop, remove per-file or
    // all. Files added here coexist with files populated by scanSourceDirectory.

    func addFiles() {
        let urls = SecurityScopeManager.shared.presentVideoFilePicker(allowMultiple: true)
        guard !urls.isEmpty else { return }
        for url in urls {
            guard !files.contains(where: { $0.url == url }) else { continue }
            let ext = url.pathExtension.lowercased()
            guard Self.supportedExtensions.contains(ext) else { continue }
            var videoFile = VideoFile(url: url)
            videoFile.bookmarkData = SecurityScopeManager.shared.createBookmark(for: url)
            files.append(videoFile)
        }
        if selectedFileID == nil { selectedFileID = files.first?.id }
    }

    func addFilesFromDrop(_ urls: [URL]) {
        for url in urls {
            guard !files.contains(where: { $0.url == url }) else { continue }
            let ext = url.pathExtension.lowercased()
            guard Self.supportedExtensions.contains(ext) else { continue }
            SecurityScopeManager.shared.startAccessing(url)
            var videoFile = VideoFile(url: url)
            videoFile.bookmarkData = SecurityScopeManager.shared.createBookmark(for: url)
            files.append(videoFile)
        }
        if selectedFileID == nil { selectedFileID = files.first?.id }
    }

    func removeFile(id: UUID) {
        if let index = files.firstIndex(where: { $0.id == id }) {
            SecurityScopeManager.shared.stopAccessing(files[index].url)
            files.remove(at: index)
        }
        if selectedFileID == id { selectedFileID = files.first?.id }
    }

    func removeAllFiles() {
        for file in files { SecurityScopeManager.shared.stopAccessing(file.url) }
        files.removeAll()
        selectedFileID = nil
    }

    // MARK: - Processing State

    // MARK: - Processing State

    /// Per-batch engine state (set by `executeBatch`). Kept for view compat.
    var isProcessing: Bool = false
    var currentJobIndex: Int = 0
    var totalJobs: Int = 0
    var overallProgress: Double = 0.0

    // MARK: - Batch Queue

    /// Queue of batches (frozen preset + jobs) to run sequentially.
    var batches: [StreamOptimizeBatch] = []

    /// Selected batch in the sidebar; nil => "New Batch" staging detail.
    var selectedBatchID: UUID?

    /// ID of the batch currently being run (nil when idle).
    var currentBatchID: UUID?

    /// True while the queue runner is executing batches.
    private(set) var isQueueProcessing: Bool = false

    /// Whole-queue cancel flag. Per-batch cancel leaves this false so the runner
    /// continues to the next pending batch.
    @ObservationIgnored private var queueCancelled: Bool = false

    /// Jobs of the currently-selected (or running) batch — view-compat mirror.
    var jobs: [StreamOptimizeJob] {
        selectedBatch?.jobs ?? currentBatch?.jobs ?? []
    }

    /// UI state bridge: nil selectedBatchID => staging; selected batch => processing.
    /// Replaced by `selectedBatchID` routing in Phase 4.
    var viewState: ViewState {
        selectedBatchID == nil ? .configuration : .processing
    }

    var selectedFile: VideoFile? {
        guard let id = selectedFileID else { return files.first }
        return files.first(where: { $0.id == id })
    }

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

    func selectOutputDirectory() {
        if let url = SecurityScopeManager.shared.presentOutputDirectoryPicker() {
            destinationDirectoryURL = url
        }
    }

    func selectDestinationDirectory() {
        selectOutputDirectory()
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
        !isQueueProcessing
            && (batches.contains(where: { $0.state == .pending }) || !files.isEmpty)
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

    // MARK: - Batch Queue Processing

    /// The currently-selected batch (sidebar selection).
    var selectedBatch: StreamOptimizeBatch? {
        guard let id = selectedBatchID else { return nil }
        return batches.first(where: { $0.id == id })
    }

    /// The batch currently being run by the queue runner.
    var currentBatch: StreamOptimizeBatch? {
        guard let id = currentBatchID else { return nil }
        return batches.first(where: { $0.id == id })
    }

    /// Snapshot the current preset + staging files into a new pending batch.
    /// Clears staging. A single file is a valid batch.
    func enqueueBatch() {
        guard QueueLogic.canEnqueue(fileCount: files.count) else { return }

        if destinationDirectoryURL == nil {
            selectOutputDirectory()
            guard destinationDirectoryURL != nil else { return }
        }

        let config = currentConfiguration
        let destURL = destinationDirectoryURL
        let batchJobs = files.map { file in
            StreamOptimizeJob(file: file, configuration: config, destinationDirectory: destURL)
        }
        for job in batchJobs { job.state = .queued }

        let batch = StreamOptimizeBatch(configuration: config, outputDirectory: destURL, jobs: batchJobs)
        batches.append(batch)

        files.removeAll()
        selectedFileID = nil
        selectedBatchID = batch.id
    }

    /// Start running the queue. Add-while-running works. If files are still staged
    /// with no pending batch, enqueue them first so a manual "Add to Queue" isn't required.
    func startProcessing() {
        if !files.isEmpty && !batches.contains(where: { $0.state == .pending }) {
            enqueueBatch()
            guard batches.contains(where: { $0.state == .pending }) else { return }
        }
        executeQueue()
    }

    func executeQueue() {
        guard !isQueueProcessing else { return }
        Task { await runQueue() }
    }

    private func runQueue() async {
        guard !isQueueProcessing else { return }
        isQueueProcessing = true
        queueCancelled = false

        while QueueLogic.shouldContinueQueue(queueCancelled: queueCancelled) {
            guard let idx = QueueLogic.firstPendingBatchIndex(batches.map(\.state)) else { break }
            let batch = batches[idx]
            batch.state = .running
            batch.startedAt = Date()
            currentBatchID = batch.id

            await executeBatch(jobs: batch.jobs)

            if batch.state == .running {
                let wasCancelled = queueCancelled
                batch.state = QueueLogic.finalizeBatchState(wasCancelled: wasCancelled)
            }
            batch.finishedAt = Date()

            if queueCancelled { break }
        }

        isQueueProcessing = false
        currentBatchID = nil
    }

    /// Cancel one batch. Pending → mark cancelled. Running → terminate the
    /// current process and mark cancelled; queue continues to next pending.
    func cancelBatch(id: UUID) {
        guard let batch = batches.first(where: { $0.id == id }) else { return }
        switch batch.state {
        case .pending:
            batch.state = .cancelled
            for job in batch.jobs where !job.state.isTerminal { job.state = .cancelled }
        case .running:
            cancelCurrentProcess()
            batch.state = .cancelled
            for job in batch.jobs where !job.state.isTerminal { job.state = .cancelled }
        default:
            break
        }
    }

    /// Cancel the whole queue.
    func cancelAllQueued() {
        queueCancelled = true
        for batch in batches where !batch.state.isTerminal {
            batch.state = .cancelled
            for job in batch.jobs where !job.state.isTerminal { job.state = .cancelled }
        }
        cancelCurrentProcess()
    }

    /// Delete a batch from the queue (never the running one).
    func deleteBatch(id: UUID) {
        guard let batch = batches.first(where: { $0.id == id }), batch.isDeletable else { return }
        for job in batch.jobs { SecurityScopeManager.shared.stopAccessing(job.file.url) }
        batches.removeAll(where: { $0.id == id })
        if selectedBatchID == id { selectedBatchID = nil }
    }

    func returnToConfiguration() {
        selectedBatchID = nil
    }

    /// Terminate the current FFmpeg process + set the per-batch cancel flag.
    /// `executeBatch` resets `cancellationRequested` at the top of each call.
    private func cancelCurrentProcess() {
        cancellationRequested = true
        if let process = currentProcess, process.isRunning {
            process.terminate()
        }
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
                nonisolated(unsafe) var pendFps: String?
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
                            pendFps = String(format: "%.1f", prog.fps)
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
                        let fp = pendFps
                        let ps = pendProcessedSeconds
                        let pr = pendProgress
                        let lg = logBatch
                        pendFrame = nil
                        pendTime = nil
                        pendFps = nil
                        pendProcessedSeconds = nil
                        pendProgress = nil
                        lastFlush = now

                        Task { @MainActor in
                            if let v = fr { job.currentFrame = v }
                            if let v = ti { job.currentTime = v }
                            if let v = fp { job.fps = v }
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
                                        job.speed = String(format: "x%.3f", speed)
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
