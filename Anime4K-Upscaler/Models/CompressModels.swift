// Anime4K-Upscaler/Models/CompressModels.swift
// Domain models for the Compress feature — encoder, content type, HDR, configuration, job, argument builder.

import Foundation
import SwiftUI
import Observation

// MARK: - Compress Encoder

/// Encoder options for the Compress feature.
enum CompressEncoder: String, CaseIterable, Identifiable, Sendable {
    case hevcVideoToolbox = "hevc_videotoolbox"
    case svtAV1           = "libsvtav1"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hevcVideoToolbox: return "HEVC (Hardware)"
        case .svtAV1:           return "SVT-AV1 (Software)"
        }
    }

    var subtitle: String {
        switch self {
        case .hevcVideoToolbox: return "VideoToolbox GPU — Fastest encoding"
        case .svtAV1:           return "SVT-AV1 CPU — Maximum storage saving"
        }
    }

    var symbolName: String {
        switch self {
        case .hevcVideoToolbox: return "bolt.fill"
        case .svtAV1:           return "cpu"
        }
    }

    /// Default quality value for each encoder.
    var defaultQuality: Int {
        switch self {
        case .hevcVideoToolbox: return 68
        case .svtAV1:           return 24
        }
    }

    /// Label describing the quality scale.
    var qualityLabel: String {
        switch self {
        case .hevcVideoToolbox: return "Quality (0–100, Higher = Better)"
        case .svtAV1:           return "CRF (0–63, Lower = Better)"
        }
    }

    /// Maximum valid quality value.
    var maxQuality: Int {
        switch self {
        case .hevcVideoToolbox: return 100
        case .svtAV1:           return 63
        }
    }

    var usesCRF: Bool { self == .svtAV1 }
}

// MARK: - Content Type

/// Content type selection for tuning anime vs live-action encoding.
enum ContentType: String, CaseIterable, Identifiable, Sendable {
    case liveAction = "live_action"
    case anime      = "anime"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .liveAction: return "Live Action"
        case .anime:      return "Anime / Animation"
        }
    }

    var subtitle: String {
        switch self {
        case .liveAction: return "Standard live-action video encoding"
        case .anime:      return "Enables B-Frames & Long GOP options"
        }
    }

    var symbolName: String {
        switch self {
        case .liveAction: return "video"
        case .anime:      return "sparkles.tv"
        }
    }
}

// MARK: - HDR Mode (auto-detected per file)

/// HDR status detected from ffprobe color_transfer metadata.
enum HDRMode: String, Sendable {
    case sdr  = "SDR"
    case hdr10 = "HDR10"

    var displayName: String {
        switch self {
        case .sdr:  return "SDR (Rec.709)"
        case .hdr10: return "HDR10 (Pass-through)"
        }
    }
}

// MARK: - Compress Configuration

/// User-configurable settings for the Compress feature.
struct CompressConfiguration: Sendable {
    var encoder: CompressEncoder = .hevcVideoToolbox
    var quality: Int = 68
    var contentType: ContentType = .liveAction
    var bFrames: Int = 3
    var longGOPEnabled: Bool = false

    static let `default` = CompressConfiguration()
}

// MARK: - Compress Job

/// A single file being compressed — tracks state, progress, and log output.
@MainActor @Observable
final class CompressJob: Identifiable {
    let id: UUID
    let file: VideoFile
    let configuration: CompressConfiguration

    var state: JobState = .idle
    var progress: Double = 0.0
    var currentFrame: Int = 0
    var currentTime: String = "00:00:00.00"
    var speed: String = "0.0x"
    var fps: String = "0"
    var outputURL: URL?
    var logLines: [String] = []
    var errorMessage: String?
    var startDate: Date?
    var endDate: Date?
    var hdrMode: HDRMode = .sdr

    @ObservationIgnored var processHandle: Process?

    init(file: VideoFile, configuration: CompressConfiguration, outputDirectory: URL? = nil) {
        self.id = UUID()
        self.file = file
        self.configuration = configuration

        let baseDir = outputDirectory ?? file.url.deletingLastPathComponent()
        let outName = "\(file.fileName)_compressed.\(file.fileExtension)"
        self.outputURL = baseDir.appendingPathComponent(outName)
    }

    var elapsedTime: TimeInterval? {
        guard let start = startDate else { return nil }
        return (endDate ?? Date()).timeIntervalSince(start)
    }

    var formattedElapsedTime: String? {
        guard let elapsed = elapsedTime else { return nil }
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        let seconds = Int(elapsed) % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    /// Append a log line (capped at 500 lines to prevent memory bloat).
    /// Uses in-place `removeSubrange` instead of allocating a new Array.
    func appendLog(_ line: String) {
        logLines.append(line)
        let overflow = logLines.count - 500
        if overflow > 0 {
            logLines.removeSubrange(0..<overflow)
        }
    }
}

// MARK: - Compress Argument Builder

/// Assembles the complete FFmpeg argument array for a compress job.
struct CompressArgumentBuilder {

    static func build(
        inputURL: URL,
        outputURL: URL,
        configuration: CompressConfiguration,
        hdrMode: HDRMode
    ) -> [String] {
        var args: [String] = []
        args.reserveCapacity(32) // ~25-30 args typical; avoids backing-store reallocations

        // Global flags
        args.append(contentsOf: ["-hide_banner", "-v", "error", "-stats"])
        args.append(contentsOf: ["-y"])
        args.append(contentsOf: ["-i", inputURL.path])

        // Map: first video, all audio, all subtitles
        args.append(contentsOf: ["-map", "0:v:0", "-map", "0:a?", "-map", "0:s?"])

        // Copy audio and subtitles
        args.append(contentsOf: ["-c:a", "copy", "-c:s", "copy"])

        // Encoder-specific arguments
        switch configuration.encoder {
        case .svtAV1:
            var svtParams = "tune=0:"
            if hdrMode == .hdr10 {
                svtParams += "enable-hdr=1:"
            } else {
                svtParams += "enable-hdr=0:color-primaries=1:transfer-characteristics=1:matrix-coefficients=1:range=1:"
            }
            svtParams = String(svtParams.dropLast()) // Remove trailing colon

            args.append(contentsOf: [
                "-c:v", "libsvtav1",
                "-preset", "4",
                "-crf", "\(configuration.quality)",
                "-pix_fmt", "yuv420p10le",
                "-svtav1-params", svtParams
            ])

        case .hevcVideoToolbox:
            args.append(contentsOf: [
                "-c:v", "hevc_videotoolbox",
                "-q:v", "\(configuration.quality)",
                "-pix_fmt", "yuv420p10le"
            ])

            // Color tags based on HDR detection
            if hdrMode == .hdr10 {
                args.append(contentsOf: [
                    "-color_primaries", "bt2020",
                    "-color_trc", "smpte2084",
                    "-colorspace", "bt2020nc"
                ])
            } else {
                args.append(contentsOf: [
                    "-color_primaries", "bt709",
                    "-color_trc", "bt709",
                    "-colorspace", "bt709",
                    "-color_range", "tv"
                ])
            }
        }

        // Anime-specific arguments
        if configuration.contentType == .anime {
            if configuration.bFrames > 0 {
                args.append(contentsOf: ["-bf", "\(configuration.bFrames)"])
            }
            if configuration.longGOPEnabled {
                args.append(contentsOf: [
                    "-g", "240",
                    "-keyint_min", "240",
                    "-sc_threshold", "0"
                ])
            }
        }

        // Output file
        args.append(outputURL.path)

        return args
    }
}
