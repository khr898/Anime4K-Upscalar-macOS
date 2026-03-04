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

    // MARK: - State

    /// All imported video files.
    var files: [VideoFile] = []

    /// Currently selected file ID in the sidebar.
    var selectedFileID: UUID?

    /// Active processing configuration.
    var configuration: JobConfiguration = .default

    /// Processing jobs for the current/last batch.
    var jobs: [ProcessingJob] = []

    /// UI state: whether the configuration panel or processing view is shown.
    var viewState: ViewState = .configuration

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

    /// Add video files via NSOpenPanel.
    func addFiles() {
        let urls = SecurityScopeManager.shared.presentVideoFilePicker(allowMultiple: true)
        guard !urls.isEmpty else { return }

        for url in urls {
            // Skip duplicates
            guard !files.contains(where: { $0.url == url }) else { continue }

            // Validate extension
            let ext = url.pathExtension.lowercased()
            guard SupportedVideoExtension.allExtensions.contains(ext) else { continue }

            var videoFile = VideoFile(url: url)
            videoFile.bookmarkData = SecurityScopeManager.shared.createBookmark(for: url)
            files.append(videoFile)
        }

        // Probe added files for metadata
        probeNewFiles()

        // Auto-select first file if none selected
        if selectedFileID == nil {
            selectedFileID = files.first?.id
        }
    }

    /// Add video files from drag-and-drop URLs.
    /// - Parameter urls: Array of file URLs from the drop.
    func addFilesFromDrop(_ urls: [URL]) {
        for url in urls {
            guard !files.contains(where: { $0.url == url }) else { continue }

            let ext = url.pathExtension.lowercased()
            guard SupportedVideoExtension.allExtensions.contains(ext) else { continue }

            SecurityScopeManager.shared.startAccessing(url)
            var videoFile = VideoFile(url: url)
            videoFile.bookmarkData = SecurityScopeManager.shared.createBookmark(for: url)
            files.append(videoFile)
        }

        probeNewFiles()

        if selectedFileID == nil {
            selectedFileID = files.first?.id
        }
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

    // MARK: - Processing

    /// Whether processing can be started.
    var canStartProcessing: Bool {
        !files.isEmpty && !engine.isProcessing
    }

    /// Start processing all files with the current configuration.
    func startProcessing() {
        guard canStartProcessing else { return }

        // Ensure output directory is selected (required for sandbox write access)
        if outputDirectoryURL == nil {
            selectOutputDirectory()
            guard outputDirectoryURL != nil else { return }
        }

        syncCompression()

        // Create jobs for all files
        jobs = files.map { file in
            ProcessingJob(file: file, configuration: configuration, outputDirectory: outputDirectoryURL)
        }

        viewState = .processing

        Task {
            await engine.executeBatch(jobs: jobs)
        }
    }

    /// Cancel all processing.
    func cancelProcessing() {
        engine.cancelAll()
    }

    /// Reset to configuration view after processing completes.
    func returnToConfiguration() {
        guard !engine.isProcessing else { return }
        viewState = .configuration
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
