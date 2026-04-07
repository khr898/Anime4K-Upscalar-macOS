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
    var contentType: ContentType = .liveAction
    var bFrames: Int = 3
    var longGOPEnabled: Bool = false

    // MARK: - Output

    var outputDirectoryURL: URL?

    var outputDirectoryDisplayName: String {
        outputDirectoryURL?.lastPathComponent ?? "Not selected"
    }

    // MARK: - Processing State

    var viewState: ViewState = .configuration
    var isProcessing: Bool = false
    var currentJobIndex: Int = 0
    var totalJobs: Int = 0
    var overallProgress: Double = 0.0
    var jobs: [CompressJob] = []

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

    func addFiles() {
        let urls = SecurityScopeManager.shared.presentVideoFilePicker(allowMultiple: true)
        guard !urls.isEmpty else { return }

        for url in urls {
            guard !files.contains(where: { $0.url == url }) else { continue }
            let ext = url.pathExtension.lowercased()
            guard SupportedVideoExtension.allExtensions.contains(ext) else { continue }

            var videoFile = VideoFile(url: url)
            videoFile.bookmarkData = SecurityScopeManager.shared.createBookmark(for: url)
            files.append(videoFile)
        }

        probeNewFiles()

        if selectedFileID == nil {
            selectedFileID = files.first?.id
        }
    }

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
        !files.isEmpty && !isProcessing
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

    // MARK: - Processing Control

    func startProcessing() {
        guard canStartProcessing else { return }

        if outputDirectoryURL == nil {
            selectOutputDirectory()
            guard outputDirectoryURL != nil else { return }
        }

        let config = CompressConfiguration(
            encoder: encoder,
            quality: quality,
            contentType: contentType,
            bFrames: bFrames,
            longGOPEnabled: longGOPEnabled
        )

        jobs = files.map { file in
            CompressJob(file: file, configuration: config, outputDirectory: outputDirectoryURL)
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
