// Anime4K-Upscaler/ViewModels/AppViewModel.swift
// Central application state and logic coordinator.

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import Observation

/// Central ViewModel for the Anime4K Upscaler application.
/// Owns file list, configuration state, processing jobs, and the processing engine.
@MainActor @Observable
final class AppViewModel {

    enum MainTab: String, CaseIterable {
        case upscale
        case compress
        case streamOptimize
    }

    // MARK: - State

    var selectedMainTab: MainTab = .upscale

    /// All imported video files.
    var files: [VideoFile] = []

    /// Currently selected file ID in the sidebar.
    var selectedFileID: UUID?

    /// Active (live) processing configuration — the preset for the next enqueued
    /// batch. Frozen per batch at enqueue time (see `enqueueBatch`).
    var configuration: JobConfiguration = .default

    // MARK: - Batch Queue

    /// Queue of batches (frozen preset + jobs) to run sequentially.
    var batches: [UpscaleBatch] = []

    /// Selected batch in the sidebar; nil => "New Batch" staging detail.
    var selectedBatchID: UUID?

    /// ID of the batch currently being run (nil when idle).
    var currentBatchID: UUID?

    /// True while the queue runner is executing batches.
    private(set) var isQueueProcessing: Bool = false

    /// Whole-queue cancel flag. Per-batch cancel leaves this false so the runner
    /// continues to the next pending batch. `@ObservationIgnored` — read by the
    /// runner on the main actor, no view binding needed.
    @ObservationIgnored private var queueCancelled: Bool = false

    /// Jobs of the currently-selected (or running) batch — view-compat mirror so
    /// `ProcessingView` reads `viewModel.jobs` unchanged when scoped to a batch.
    var jobs: [ProcessingJob] {
        selectedBatch?.jobs ?? currentBatch?.jobs ?? []
    }

    /// UI state bridge: nil selectedBatchID => configuration/staging detail; a
    /// selected batch => processing-style detail. Replaced by `selectedBatchID`
    /// routing in Phase 4; kept computed so existing views compile during migration.
    var viewState: ViewState {
        selectedBatchID == nil ? .configuration : .processing
    }

    /// Compression preset for picker binding.
    var compressionPreset: CompressionPreset = .visuallyLossless

    /// Custom quality value (used when compressionPreset == .customQuality).
    var customQualityValue: Int = 68

    /// Custom bitrate value in Mbps (used when compressionPreset == .fixedBitrate).
    var customBitrateValue: Int = 45

    /// Dependency validation errors (shown on launch if dependencies are missing).
    var dependencyErrors: [String] = []

    /// Whether to show the dependency alert.
    var showDependencyAlert: Bool = false

    /// User-selected output directory (sandbox-safe). If nil, prompts before processing.
    var outputDirectoryURL: URL?

    /// Display name for the selected output directory.
    var outputDirectoryDisplayName: String {
        outputDirectoryURL?.lastPathComponent ?? "Not selected"
    }

    // MARK: - Engine

    /// The processing engine instance.
    /// `let` prevents the @Observable macro from instrumenting this property,
    /// eliminating spurious view invalidations when unrelated AppViewModel
    /// properties change. Views still observe `engine.isProcessing` etc.
    /// through ProcessingEngine's own @Observable conformance.
    let engine = ProcessingEngine()

    // MARK: - View State Enum

    enum ViewState: String {
        case configuration = "configuration"
        case processing    = "processing"
    }

    // MARK: - Initialization

    init() {
        validateDependencies()
        if dependencyErrors.contains("libMoltenVK.dylib") {
            configuration.mode = .modeA_Fast
        }
    }

    // MARK: - Dependency Validation

    /// Check that bundled FFmpeg and shaders are present.
    func validateDependencies() {
        let missing = FFmpegLocator.validateDependencies()
        if !missing.isEmpty {
            dependencyErrors = missing
            showDependencyAlert = true
        }
    }

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

        // Probe added files for metadata
        probeNewFiles()

        // Auto-select first file if none selected
        if selectedFileID == nil {
            selectedFileID = files.first?.id
        }
    }

    /// Add video files from drag-and-drop URLs (files, folders, or mixed selections).
    /// - Parameter urls: Array of file or folder URLs from the drop.
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

    /// Enqueue a batch immediately: if staging has files, enqueues them; if staging
    /// is empty, prompts file/folder picker, stages them, and enqueues in one action.
    func addAndEnqueueBatch() {
        if files.isEmpty {
            let urls = SecurityScopeManager.shared.presentVideoFilePicker(allowMultiple: true)
            guard !urls.isEmpty else { return }

            let discovered = FileDiscovery.resolveVideoFiles(from: urls)
            guard !discovered.isEmpty else { return }

            for videoFile in discovered {
                guard !files.contains(where: { $0.url == videoFile.url }) else { continue }
                files.append(videoFile)
            }
            probeNewFiles()
        }
        enqueueBatch()
    }

    /// Remove a file from the list.
    /// - Parameter id: The UUID of the file to remove.
    func removeFile(id: UUID) {
        if let index = files.firstIndex(where: { $0.id == id }) {
            SecurityScopeManager.shared.stopAccessing(files[index].url)
            files.remove(at: index)
        }
        if selectedFileID == id {
            selectedFileID = files.first?.id
        }
    }

    /// Remove all files.
    func removeAllFiles() {
        SecurityScopeManager.shared.stopAccessingAll()
        files.removeAll()
        selectedFileID = nil
    }

    /// Remove selected file.
    func removeSelectedFile() {
        guard let id = selectedFileID else { return }
        removeFile(id: id)
    }

    // MARK: - Metadata Probing

    /// Probe all files that lack duration/resolution metadata.
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

    // MARK: - Configuration Sync

    /// Synchronize the compression configuration from picker/slider state.
    func syncCompression() {
        switch compressionPreset {
        case .visuallyLossless:
            configuration.compression = .visuallyLossless
        case .balanced:
            configuration.compression = .balanced
        case .customQuality:
            configuration.compression = .customQuality(customQualityValue)
        case .fixedBitrate:
            configuration.compression = .fixedBitrate(customBitrateValue)
        }
    }

    /// Update custom quality value and sync.
    func updateCustomQuality(_ value: Int) {
        let maxVal = configuration.codec.usesCRF ? 63 : 100
        customQualityValue = max(0, min(value, maxVal))
        syncCompression()
    }

    /// Update custom bitrate value and sync.
    func updateCustomBitrate(_ value: Int) {
        customBitrateValue = max(1, min(value, 200))
        syncCompression()
    }

    /// Update the quality value defaults when codec changes.
    func onCodecChanged() {
        if configuration.codec.usesCRF {
            if compressionPreset == .customQuality && customQualityValue > 63 {
                customQualityValue = 24
            }
        } else {
            if compressionPreset == .customQuality && customQualityValue > 100 {
                customQualityValue = 68
            }
        }
        syncCompression()
    }

    // MARK: - Output Directory

    /// Let the user choose an output directory via NSOpenPanel.
    func selectOutputDirectory() {
        if let url = SecurityScopeManager.shared.presentOutputDirectoryPicker() {
            outputDirectoryURL = url
        }
    }

    // MARK: - Batch Queue Processing

    /// The currently-selected batch (sidebar selection).
    var selectedBatch: UpscaleBatch? {
        guard let id = selectedBatchID else { return nil }
        return batches.first(where: { $0.id == id })
    }

    /// The batch currently being run by the queue runner.
    var currentBatch: UpscaleBatch? {
        guard let id = currentBatchID else { return nil }
        return batches.first(where: { $0.id == id })
    }

    /// Whether the queue can be started: at least one pending batch OR staged
    /// files that can be enqueued on the fly, and not already running. Lets the
    /// "Start Processing" button upscale a single staged file without a manual
    /// "Add to Queue" click — `startProcessing` enqueues staged files first.
    var canStartProcessing: Bool {
        !isQueueProcessing
            && (batches.contains(where: { $0.state == .pending }) || !files.isEmpty)
    }

    /// Snapshot the current preset + staging files into a new pending batch and
    /// append it to the queue. Clears staging. A single file is a valid batch.
    /// Prompts for an output directory at enqueue time (frozen per batch so
    /// different batches may target different directories).
    func enqueueBatch() {
        guard QueueLogic.canEnqueue(fileCount: files.count) else { return }

        if outputDirectoryURL == nil {
            selectOutputDirectory()
            guard outputDirectoryURL != nil else { return }
        }

        syncCompression()

        let config = configuration
        let outDir = outputDirectoryURL
        let batchJobs = files.map { file in
            ProcessingJob(file: file, configuration: config, outputDirectory: outDir)
        }
        for job in batchJobs { job.state = .queued }

        let batch = UpscaleBatch(configuration: config, outputDirectory: outDir, jobs: batchJobs)
        batches.append(batch)

        // Clear staging — files now live on the batch's jobs.
        files.removeAll()
        selectedFileID = nil
        selectedBatchID = batch.id
    }

    /// Start running the queue (all pending batches, sequentially). Add-while-
    /// running works: `enqueueBatch` appends during the run and the runner picks
    /// it up next loop turn. If files are still staged with no pending batch
    /// (e.g. the "Start Processing" button clicked on a single staged file),
    /// enqueue them first so a manual "Add to Queue" isn't required.
    func startProcessing() {
        if !files.isEmpty && !batches.contains(where: { $0.state == .pending }) {
            enqueueBatch()
            guard batches.contains(where: { $0.state == .pending }) else { return }
        }
        executeQueue()
    }

    /// Run all pending batches in order. `ProcessingEngine` is reused per batch
    /// with no engine change — its `cancellationRequested` resets at the top of
    /// each `executeBatch` call, so a per-batch cancel stops the current batch
    /// and the runner continues; a whole-queue cancel sets `queueCancelled` and
    /// the runner stops. `// ponytail: single-actor queue, no lock needed`
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

            await engine.executeBatch(jobs: batch.jobs)

            // If not pre-cancelled mid-flight (cancelBatch/cancelAllQueued already
            // set .cancelled), finalize based on whether this batch was cancelled.
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

    /// Cancel one batch. Pending → mark cancelled (runner skips it). Running →
    /// terminate the current process via `engine.cancelAll()` and mark cancelled;
    /// `queueCancelled` stays false so the runner continues to the next pending
    /// batch. Terminal → no-op.
    func cancelBatch(id: UUID) {
        guard let batch = batches.first(where: { $0.id == id }) else { return }
        switch batch.state {
        case .pending:
            batch.state = .cancelled
            for job in batch.jobs where !job.state.isTerminal { job.state = .cancelled }
        case .running:
            engine.cancelAll()
            batch.state = .cancelled
            for job in batch.jobs where !job.state.isTerminal { job.state = .cancelled }
        default:
            break
        }
    }

    /// Cancel the whole queue: stop the current process and mark every non-
    /// terminal batch cancelled.
    func cancelAllQueued() {
        queueCancelled = true
        for batch in batches where !batch.state.isTerminal {
            batch.state = .cancelled
            for job in batch.jobs where !job.state.isTerminal { job.state = .cancelled }
        }
        engine.cancelAll()
    }

    /// Delete a batch from the queue (never the running one). Releases the
    /// security scope of its files.
    func deleteBatch(id: UUID) {
        guard let batch = batches.first(where: { $0.id == id }), batch.isDeletable else { return }
        for job in batch.jobs { SecurityScopeManager.shared.stopAccessing(job.file.url) }
        batches.removeAll(where: { $0.id == id })
        if selectedBatchID == id { selectedBatchID = nil }
    }

    /// Return to the "New Batch" staging detail.
    func returnToConfiguration() {
        selectedBatchID = nil
    }

    // MARK: - Computed Properties

    /// The currently selected file.
    var selectedFile: VideoFile? {
        guard let id = selectedFileID else { return nil }
        return files.first(where: { $0.id == id })
    }

    /// Total file size of all imported files.
    var totalFileSize: String {
        let total = files.reduce(Int64(0)) { $0 + $1.fileSizeBytes }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    /// Total duration of all imported files.
    var totalDuration: String? {
        let durations = files.compactMap(\.durationSeconds)
        guard !durations.isEmpty else { return nil }
        let total = durations.reduce(0, +)
        let hours = Int(total) / 3600
        let minutes = (Int(total) % 3600) / 60
        let seconds = Int(total) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    /// Summary string for the batch processing header.
    var batchSummary: String {
        let modeStr = configuration.mode.displayName
        let scaleStr = configuration.resolution.displayName
        let codecStr = configuration.codec.displayName
        return "\(files.count) file\(files.count == 1 ? "" : "s") • \(modeStr) • \(scaleStr) • \(codecStr)"
    }

    /// Number of completed jobs.
    var completedJobCount: Int {
        jobs.filter { $0.state == .completed }.count
    }

    /// Number of failed jobs.
    var failedJobCount: Int {
        jobs.filter { $0.state == .failed }.count
    }

    /// Whether all jobs have finished (completed, failed, or cancelled).
    var allJobsFinished: Bool {
        !jobs.isEmpty && jobs.allSatisfy { $0.state.isTerminal }
    }

}
