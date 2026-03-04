// Anime4K-Upscaler/Models/StreamOptimizeModels.swift
// Domain models for the Stream Optimize feature — configuration, enums, job, argument builder.

import Foundation
import SwiftUI
import Observation

// MARK: - Stream Encoder

/// Video encoder for stream optimization.
enum StreamEncoder: String, CaseIterable, Identifiable, Sendable {
    case hevcVideoToolbox = "hevc_videotoolbox"
    case h264VideoToolbox = "h264_videotoolbox"
    case svtAV1           = "libsvtav1"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hevcVideoToolbox: return "HEVC (Hardware)"
        case .h264VideoToolbox: return "H.264 (Hardware)"
        case .svtAV1:           return "AV1 (Software)"
        }
    }

    var subtitle: String {
        switch self {
        case .hevcVideoToolbox: return "VideoToolbox GPU — Best balance of quality, size & compatibility"
        case .h264VideoToolbox: return "VideoToolbox GPU — Maximum device compatibility"
        case .svtAV1:           return "SVT-AV1 CPU — Best compression, modern players only"
        }
    }

    var symbolName: String {
        switch self {
        case .hevcVideoToolbox: return "bolt.fill"
        case .h264VideoToolbox: return "bolt"
        case .svtAV1:           return "cpu"
        }
    }

    /// Default quality value (HEVC/H264 use -q:v 0–100 higher=better, AV1 uses CRF 0–63 lower=better).
    var defaultQuality: Int {
        switch self {
        case .hevcVideoToolbox: return 65
        case .h264VideoToolbox: return 65
        case .svtAV1:           return 28
        }
    }

    var maxQuality: Int {
        switch self {
        case .hevcVideoToolbox: return 100
        case .h264VideoToolbox: return 100
        case .svtAV1:           return 63
        }
    }

    var qualityLabel: String {
        switch self {
        case .hevcVideoToolbox, .h264VideoToolbox:
            return "Quality (0–100, Higher = Better)"
        case .svtAV1:
            return "CRF (0–63, Lower = Better)"
        }
    }

    var usesCRF: Bool { self == .svtAV1 }

    /// Supported profiles for this encoder.
    var availableProfiles: [StreamProfile] {
        switch self {
        case .hevcVideoToolbox: return [.main, .main10]
        case .h264VideoToolbox: return [.high, .main, .baseline]
        case .svtAV1:           return [.main]  // AV1 main profile
        }
    }

    /// Default profile for this encoder.
    var defaultProfile: StreamProfile {
        switch self {
        case .hevcVideoToolbox: return .main10
        case .h264VideoToolbox: return .high
        case .svtAV1:           return .main
        }
    }

    /// Supported pixel formats for this encoder.
    var availablePixelFormats: [StreamPixelFormat] {
        switch self {
        case .hevcVideoToolbox: return [.p010le, .nv12]
        case .h264VideoToolbox: return [.nv12, .yuv420p]
        case .svtAV1:           return [.yuv420p10le, .yuv420p]
        }
    }

    /// Default pixel format for this encoder.
    var defaultPixelFormat: StreamPixelFormat {
        switch self {
        case .hevcVideoToolbox: return .p010le
        case .h264VideoToolbox: return .nv12
        case .svtAV1:           return .yuv420p10le
        }
    }
}

// MARK: - Stream Profile

/// Encoder profile options.
enum StreamProfile: String, CaseIterable, Identifiable, Sendable {
    case main10   = "main10"
    case main     = "main"
    case high     = "high"
    case baseline = "baseline"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .main10:   return "Main 10"
        case .main:     return "Main"
        case .high:     return "High"
        case .baseline: return "Baseline"
        }
    }

    var subtitle: String {
        switch self {
        case .main10:   return "10-bit color depth — Best HDR & gradient quality"
        case .main:     return "8-bit standard profile"
        case .high:     return "H.264 High — Best H.264 quality"
        case .baseline: return "Maximum compatibility (older devices)"
        }
    }
}

// MARK: - Stream Pixel Format

/// Pixel format options.
enum StreamPixelFormat: String, CaseIterable, Identifiable, Sendable {
    case p010le      = "p010le"
    case nv12        = "nv12"
    case yuv420p     = "yuv420p"
    case yuv420p10le = "yuv420p10le"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .p010le:      return "P010LE (10-bit)"
        case .nv12:        return "NV12 (8-bit HW)"
        case .yuv420p:     return "YUV420P (8-bit)"
        case .yuv420p10le: return "YUV420P10LE (10-bit)"
        }
    }
}

// MARK: - Stream Audio Mode

/// Audio handling strategy.
enum StreamAudioMode: String, CaseIterable, Identifiable, Sendable {
    case copy       = "copy"
    case aacTranscode = "aac"
    case aac128     = "aac_128"
    case aac192     = "aac_192"
    case aac256     = "aac_256"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .copy:       return "Copy (Passthrough)"
        case .aacTranscode: return "AAC (Auto Bitrate)"
        case .aac128:     return "AAC 128 kbps"
        case .aac192:     return "AAC 192 kbps"
        case .aac256:     return "AAC 256 kbps"
        }
    }

    var subtitle: String {
        switch self {
        case .copy:       return "Fastest — keeps original audio untouched"
        case .aacTranscode: return "Re-encode to AAC with FFmpeg default bitrate"
        case .aac128:     return "Good for spoken content & podcasts"
        case .aac192:     return "Balanced quality for music & movies"
        case .aac256:     return "High quality audio for critical listening"
        }
    }

    var symbolName: String {
        switch self {
        case .copy:          return "arrow.right.circle"
        case .aacTranscode:  return "waveform"
        case .aac128:        return "speaker.wave.1"
        case .aac192:        return "speaker.wave.2"
        case .aac256:        return "speaker.wave.3"
        }
    }

    /// Whether this mode copies audio without re-encoding.
    var isCopy: Bool { self == .copy }
}

// MARK: - Stream Subtitle Mode

/// Subtitle handling strategy for MP4 output.
enum StreamSubtitleMode: String, CaseIterable, Identifiable, Sendable {
    case movText = "mov_text"
    case copy    = "copy"
    case strip   = "strip"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .movText: return "MOV Text (MP4 Compatible)"
        case .copy:    return "Copy (Passthrough)"
        case .strip:   return "Strip All Subtitles"
        }
    }

    var subtitle: String {
        switch self {
        case .movText: return "Converts subtitles to MP4-native text — Best for streaming"
        case .copy:    return "Keeps original format — May fail in MP4 container"
        case .strip:   return "Removes all subtitle tracks"
        }
    }

    var symbolName: String {
        switch self {
        case .movText: return "text.bubble"
        case .copy:    return "arrow.right.circle"
        case .strip:   return "text.badge.minus"
        }
    }
}

// MARK: - Keyframe Interval

/// Keyframe interval presets for seeking performance.
enum KeyframeInterval: String, CaseIterable, Identifiable, Sendable {
    case oneSecond   = "1s"
    case twoSeconds  = "2s"
    case threeSeconds = "3s"
    case fiveSeconds = "5s"
    case tenSeconds  = "10s"

    var id: String { rawValue }

    /// Interval in seconds.
    var seconds: Int {
        switch self {
        case .oneSecond:    return 1
        case .twoSeconds:   return 2
        case .threeSeconds: return 3
        case .fiveSeconds:  return 5
        case .tenSeconds:   return 10
        }
    }

    var displayName: String {
        switch self {
        case .oneSecond:    return "1 second"
        case .twoSeconds:   return "2 seconds"
        case .threeSeconds: return "3 seconds"
        case .fiveSeconds:  return "5 seconds"
        case .tenSeconds:   return "10 seconds"
        }
    }

    var subtitle: String {
        switch self {
        case .oneSecond:    return "Instant seeking — Larger file size"
        case .twoSeconds:   return "Excellent seeking — Recommended for streaming"
        case .threeSeconds: return "Good seeking — Balanced"
        case .fiveSeconds:  return "Moderate seeking — Smaller file"
        case .tenSeconds:   return "Slow seeking — Smallest file"
        }
    }
}

// MARK: - Stream Optimize Configuration

/// User-configurable settings for stream optimization.
/// Defaults are tuned for Apple device streaming with quick seeking.
struct StreamOptimizeConfiguration: Sendable {
    var encoder: StreamEncoder         = .hevcVideoToolbox
    var quality: Int                   = 65
    var profile: StreamProfile         = .main10
    var pixelFormat: StreamPixelFormat = .p010le
    var audioMode: StreamAudioMode     = .copy
    var subtitleMode: StreamSubtitleMode = .movText
    var keyframeInterval: KeyframeInterval = .twoSeconds
    var faststart: Bool                = true
    var allowSWFallback: Bool          = true

    /// Production-ready defaults optimized for streaming delivery.
    static let `default` = StreamOptimizeConfiguration()
}

// MARK: - Stream Optimize Job

/// A single file being stream-optimized — tracks state, progress, and log output.
@MainActor @Observable
final class StreamOptimizeJob: Identifiable {
    let id: UUID
    let file: VideoFile
    let configuration: StreamOptimizeConfiguration

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

    @ObservationIgnored var processHandle: Process?

    init(file: VideoFile, configuration: StreamOptimizeConfiguration, destinationDirectory: URL) {
        self.id = UUID()
        self.file = file
        self.configuration = configuration
        self.outputURL = destinationDirectory.appendingPathComponent("\(file.fileName)_streaming.mp4")
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

// MARK: - Stream Optimize Argument Builder

/// Assembles FFmpeg arguments for stream optimization.
/// Produces output superb for streaming: frequent keyframes for quick seeking,
/// faststart moov atom, proper container metadata, and hardware-accelerated encoding.
struct StreamOptimizeArgumentBuilder {

    static func build(
        inputURL: URL,
        outputURL: URL,
        configuration: StreamOptimizeConfiguration
    ) -> [String] {
        var args: [String] = []
        args.reserveCapacity(32) // ~25-30 args typical; avoids backing-store reallocations

        // Global flags
        args.append(contentsOf: ["-nostdin", "-hide_banner", "-v", "error", "-stats"])
        args.append(contentsOf: ["-y"])
        args.append(contentsOf: ["-i", inputURL.path])

        // Stream mapping
        if configuration.subtitleMode == .strip {
            // Map video + audio only, strip subtitles
            args.append(contentsOf: ["-map", "0:v:0", "-map", "0:a?"])
        } else {
            // Map all streams
            args.append(contentsOf: ["-map", "0:v:0", "-map", "0:a?", "-map", "0:s?"])
        }

        // ─── VIDEO ENCODER ───
        switch configuration.encoder {
        case .hevcVideoToolbox:
            args.append(contentsOf: [
                "-c:v", "hevc_videotoolbox",
                "-q:v", "\(configuration.quality)",
                "-profile:v", configuration.profile.rawValue,
                "-pix_fmt", configuration.pixelFormat.rawValue
            ])

            if configuration.allowSWFallback {
                args.append(contentsOf: ["-allow_sw", "1"])
            }

        case .h264VideoToolbox:
            args.append(contentsOf: [
                "-c:v", "h264_videotoolbox",
                "-q:v", "\(configuration.quality)",
                "-profile:v", configuration.profile.rawValue,
                "-pix_fmt", configuration.pixelFormat.rawValue
            ])

            if configuration.allowSWFallback {
                args.append(contentsOf: ["-allow_sw", "1"])
            }

        case .svtAV1:
            args.append(contentsOf: [
                "-c:v", "libsvtav1",
                "-preset", "6",
                "-crf", "\(configuration.quality)",
                "-pix_fmt", configuration.pixelFormat.rawValue,
                "-svtav1-params", "tune=0"
            ])
        }

        // ─── KEYFRAME INTERVAL (Critical for quick seeking) ───
        // force_key_frames guarantees a keyframe exactly every N seconds,
        // independent of scene detection. This is essential for streaming
        // players that need frame-accurate seek points.
        let kfSeconds = configuration.keyframeInterval.seconds
        args.append(contentsOf: [
            "-force_key_frames", "expr:gte(t,n_forced*\(kfSeconds))"
        ])

        // ─── AUDIO ───
        switch configuration.audioMode {
        case .copy:
            args.append(contentsOf: ["-c:a", "copy"])
        case .aacTranscode:
            args.append(contentsOf: ["-c:a", "aac"])
        case .aac128:
            args.append(contentsOf: ["-c:a", "aac", "-b:a", "128k"])
        case .aac192:
            args.append(contentsOf: ["-c:a", "aac", "-b:a", "192k"])
        case .aac256:
            args.append(contentsOf: ["-c:a", "aac", "-b:a", "256k"])
        }

        // ─── SUBTITLES ───
        switch configuration.subtitleMode {
        case .movText:
            args.append(contentsOf: ["-c:s", "mov_text"])
        case .copy:
            args.append(contentsOf: ["-c:s", "copy"])
        case .strip:
            break // Already excluded via -map
        }

        // ─── STREAMING OPTIMIZATION ───
        if configuration.faststart {
            // Moves moov atom to the beginning of the file.
            // This is CRITICAL for streaming: players can start playback
            // immediately without downloading the entire file first.
            args.append(contentsOf: ["-movflags", "+faststart"])
        }

        // Output file
        args.append(outputURL.path)

        return args
    }
}
