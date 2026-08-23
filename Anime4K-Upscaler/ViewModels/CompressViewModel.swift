// Anime4K-Upscaler/ViewModels/CompressViewModel.swift
// ViewModel for the Compress feature — file management, configuration, processing engine.

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import Observation
import IOKit.pwr_mgt

/// Central ViewModel for the Compress feature.
/// Manages file list, encoder/quality/content configuration, HDR detection,
/// and FFmpeg process execution with progress tracking.
@MainActor @Observable
final class CompressViewModel {

    // MARK: - File State

    var files: [VideoFile] = []
    var selectedFileID: UUID?

    // MARK: - Configuration

    var encoder: CompressEncoder = .hevcVideoToolbox
    var quality: Int = 68
    var svtAV1Preset: Int = 4
    var contentType: ContentType = .liveAction
    var bFrames: Int = 3
    var longGOPEnabled: Bool = false

    // MARK: - Output

    var outputDirectoryURL: URL?

    var outputDirectoryDisplayName: String {
        outputDirectoryURL?.lastPathComponent ?? "Not selected"
    }

    // MARK: - Processing State

    /// Per-batch engine state (set by `executeBatch`). Kept for view compat.
    var isProcessing: Bool = false
    var currentJobIndex: Int = 0
    var totalJobs: Int = 0
    var overallProgress: Double = 0.0

    // MARK: - Batch Queue

    /// Queue of batches (frozen preset + jobs) to run sequentially.
    var batches: [CompressBatch] = []

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
    var jobs: [CompressJob] {
        selectedBatch?.jobs ?? currentBatch?.jobs ?? []
    }

    /// UI state bridge: nil selectedBatchID => staging; selected batch => processing.
    /// Replaced by `selectedBatchID` routing in Phase 4.
    var viewState: ViewState {
        selectedBatchID == nil ? .configuration : .processing
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

    // MARK: - File Management

    /// Add video files via NSOpenPanel (supports files, folders, or mixed selections).
    func addFiles() {
        let urls = SecurityScopeManager.shared.presentVideoFilePicker(allowMultiple: true)
        guard !urls.isEmpty else { return }

        let discovered = FileDiscovery.resolveVideoFiles(from: urls)
        for videoFile in discovered {
            guard !files.contains(where: { $0.url == videoFile.url }) else { continue }
            files.append(videoFile)
        }

        probeNewFiles()

        if selectedFileID == nil {
            selectedFileID = files.first?.id
        }
    }

    /// Add video files from drag-and-drop URLs (files, folders, or mixed selections).
    func addFilesFromDrop(_ urls: [URL]) {
        let discovered = FileDiscovery.resolveVideoFiles(from: urls)
        for videoFile in discovered {
            guard !files.contains(where: { $0.url == videoFile.url }) else { continue }
            files.append(videoFile)
        }

        probeNewFiles()

        if selectedFileID == nil {
            selectedFileID = files.first?.id
        }
    }


    func removeFile(id: UUID) {
        if let index = files.firstIndex(where: { $0.id == id }) {
            SecurityScopeManager.shared.stopAccessing(files[index].url)
            files.remove(at: index)
        }
        if selectedFileID == id {
            selectedFileID = files.first?.id
        }
    }

    func removeAllFiles() {
        for file in files {
            SecurityScopeManager.shared.stopAccessing(file.url)
        }
        files.removeAll()
        selectedFileID = nil
    }

    // MARK: - Metadata Probing

    private func probeNewFiles() {
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

    // MARK: - Configuration Helpers

    func onEncoderChanged() {
        quality = encoder.defaultQuality
    }

    func updateQuality(_ value: Int) {
        quality = max(0, min(value, encoder.maxQuality))
    }

    var selectedFile: VideoFile? {
        guard let id = selectedFileID else { return nil }
        return files.first(where: { $0.id == id })
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

    var canStartProcessing: Bool {
        !isQueueProcessing
            && (batches.contains(where: { $0.state == .pending }) || !files.isEmpty)
    }

    /// Snapshot of the current UI config fields into a `CompressConfiguration`.
    private var currentConfiguration: CompressConfiguration {
        CompressConfiguration(
            encoder: encoder,
            quality: quality,
            svtAV1Preset: svtAV1Preset,
            contentType: contentType,
            bFrames: bFrames,
            longGOPEnabled: longGOPEnabled
        )
    }

    var batchSummary: String {
        "\(files.count) file\(files.count == 1 ? "" : "s") • \(encoder.displayName) • \(contentType.displayName)"
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

    // MARK: - Output Directory

    func selectOutputDirectory() {
        if let url = SecurityScopeManager.shared.presentOutputDirectoryPicker() {
            outputDirectoryURL = url
        }
    }

    // MARK: - Batch Queue Processing

    /// The currently-selected batch (sidebar selection).
    var selectedBatch: CompressBatch? {
        guard let id = selectedBatchID else { return nil }
        return batches.first(where: { $0.id == id })
    }

    /// The batch currently being run by the queue runner.
    var currentBatch: CompressBatch? {
        guard let id = currentBatchID else { return nil }
        return batches.first(where: { $0.id == id })
    }

    /// Snapshot the current preset + staging files into a new pending batch.
    /// Clears staging. A single file is a valid batch.
    func enqueueBatch() {
        guard QueueLogic.canEnqueue(fileCount: files.count) else { return }

        if outputDirectoryURL == nil {
            selectOutputDirectory()
            guard outputDirectoryURL != nil else { return }
        }

        let config = currentConfiguration
        let outDir = outputDirectoryURL
        let batchJobs = files.map { file in
            CompressJob(file: file, configuration: config, outputDirectory: outDir)
        }
        for job in batchJobs { job.state = .queued }

        let batch = CompressBatch(configuration: config, outputDirectory: outDir, jobs: batchJobs)
        batches.append(batch)

        files.removeAll()
        selectedFileID = nil
        selectedBatchID = batch.id
    }

    /// Start running the queue. Add-while-running works: `enqueueBatch` appends
    /// during the run and the runner picks it up next loop turn. If files are
    /// still staged with no pending batch, enqueue them first so a manual
    /// "Add to Queue" isn't required.
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
    /// `executeBatch` resets `cancellationRequested` at the top of each call, so
    /// this is safe to call for a per-batch cancel without poisoning the next batch.
    private func cancelCurrentProcess() {
        cancellationRequested = true
        if let process = currentProcess, process.isRunning {
            process.terminate()
        }
    }

    // MARK: - Batch Execution

    private func executeBatch(jobs: [CompressJob]) async {
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

    private func executeJob(_ job: CompressJob) async {
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

        // Detect HDR via ffprobe color_transfer
        let colorTransfer = await DurationProbe.probeColorTransfer(url: job.file.url)
        let hdrMode: HDRMode = (colorTransfer?.contains("smpte2084") == true) ? .hdr10 : .sdr
        job.hdrMode = hdrMode

        let arguments = CompressArgumentBuilder.build(
            inputURL: job.file.url,
            outputURL: outputURL,
            configuration: job.configuration,
            hdrMode: hdrMode
        )

        let totalDuration = job.file.durationSeconds ?? 0

        job.state = .running
        job.progress = 0.0
        job.startDate = Date()
        job.appendLog("$ ffmpeg \(arguments.joined(separator: " "))")
        job.appendLog("HDR: \(hdrMode.displayName)")

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
                    // Compress uses -stats on stderr; stdout is unused but drain it
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
                            job.appendLog("✅ Compression completed successfully.")
                        } else if proc.terminationReason == .uncaughtSignal {
                            job.state = .cancelled
                            job.appendLog("🛑 Compression cancelled by user.")
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
        let reason = "Anime4K Upscaler — Compress is processing video" as CFString
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
            reason: "Video compression in progress"
        )
    }

    private func endAppNapPrevention() {
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
    }
}
