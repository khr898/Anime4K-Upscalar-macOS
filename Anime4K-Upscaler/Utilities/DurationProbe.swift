// Anime4K-Upscaler/Utilities/DurationProbe.swift
// Probes video files for duration and resolution using bundled ffprobe.

import Foundation

/// Uses the bundled `ffprobe` to extract video metadata (duration, resolution).
struct DurationProbe {

    // MARK: - Probe Result

    struct ProbeResult: Sendable {
        let durationSeconds: Double
        let width: Int
        let height: Int
    }

    // MARK: - Probe Execution

    /// Probe a video file for duration and resolution.
    /// Runs ffprobe synchronously on a background thread.
    /// - Parameter url: The video file URL.
    /// - Returns: A ProbeResult with duration and dimensions, or nil on failure.
    static func probe(url: URL) async -> ProbeResult? {
        guard let ffprobeURL = FFmpegLocator.ffprobeURL,
              FileManager.default.isExecutableFile(atPath: ffprobeURL.path) else {
            return nil
        }

        // Run duration and stream info probes concurrently
        async let durationResult = probeDuration(ffprobeURL: ffprobeURL, fileURL: url)
        async let streamResult = probeStreams(ffprobeURL: ffprobeURL, fileURL: url)

        guard let duration = await durationResult else { return nil }
        let streams = await streamResult

        return ProbeResult(
            durationSeconds: duration,
            width: streams?.width ?? 0,
            height: streams?.height ?? 0
        )
    }

    // MARK: - Duration Probe

    private static func probeDuration(ffprobeURL: URL, fileURL: URL) async -> Double? {
        let args = [
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "csv=p=0",
            fileURL.path
        ]

        guard let output = await runFFprobe(ffprobeURL: ffprobeURL, arguments: args) else {
            return nil
        }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(trimmed)
    }

    // MARK: - Stream Info Probe

    private struct StreamInfo {
        let width: Int
        let height: Int
    }

    private static func probeStreams(ffprobeURL: URL, fileURL: URL) async -> StreamInfo? {
        let args = [
            "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=width,height",
            "-of", "csv=p=0:s=x",
            fileURL.path
        ]

        guard let output = await runFFprobe(ffprobeURL: ffprobeURL, arguments: args) else {
            return nil
        }

        // Output format: "1920x1080\n" or "1920x1080"
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.split(separator: "x")
        guard components.count == 2,
              let width = Int(components[0]),
              let height = Int(components[1]) else {
            return nil
        }

        return StreamInfo(width: width, height: height)
    }

    // MARK: - Process Runner

    private static func runFFprobe(ffprobeURL: URL, arguments: [String]) async -> String? {
        let capturedEnv = FFmpegLocator.processEnvironment()
        return await withCheckedContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                let process = Process()
                process.executableURL = ffprobeURL
                process.arguments = arguments
                process.environment = capturedEnv

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()

                    // CRITICAL: Read pipe data BEFORE waitUntilExit to prevent
                    // deadlock when pipe buffer fills (~64KB). ffprobe output is
                    // small, but this is the correct ordering for all pipe usage.
                    let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    // Drain stderr to prevent buffer fill on error output
                    _ = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                    process.waitUntilExit()

                    // Cleanup file descriptors
                    try? stdoutPipe.fileHandleForReading.close()
                    try? stderrPipe.fileHandleForReading.close()

                    let output = String(data: data, encoding: .utf8)
                    continuation.resume(returning: process.terminationStatus == 0 ? output : nil)
                } catch {
                    try? stdoutPipe.fileHandleForReading.close()
                    try? stderrPipe.fileHandleForReading.close()
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Batch Probe

    /// Probe multiple files concurrently, returning results keyed by URL.
    /// - Parameter urls: Array of video file URLs to probe.
    /// - Returns: Dictionary mapping each URL to its probe result (nil if probe failed).
    static func batchProbe(urls: [URL]) async -> [URL: ProbeResult?] {
        await withTaskGroup(of: (URL, ProbeResult?).self, returning: [URL: ProbeResult?].self) { group in
            for url in urls {
                group.addTask {
                    let result = await probe(url: url)
                    return (url, result)
                }
            }

            var results: [URL: ProbeResult?] = [:]
            for await (url, result) in group {
                results[url] = result
            }
            return results
        }
    }

    // MARK: - Color Transfer Probe (for HDR detection)

    /// Probe a video file for its color_transfer metadata.
    /// Used by the Compress feature to auto-detect HDR vs SDR content.
    /// - Parameter url: The video file URL.
    /// - Returns: The color_transfer string (e.g. "bt709", "smpte2084"), or nil on failure.
    static func probeColorTransfer(url: URL) async -> String? {
        guard let ffprobeURL = FFmpegLocator.ffprobeURL,
              FileManager.default.isExecutableFile(atPath: ffprobeURL.path) else {
            return nil
        }

        let args = [
            "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=color_transfer",
            "-of", "csv=p=0",
            url.path
        ]

        guard let output = await runFFprobe(ffprobeURL: ffprobeURL, arguments: args) else {
            return nil
        }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
