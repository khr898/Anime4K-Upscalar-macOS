// Anime4K-Upscaler/Models/Models.swift
// Complete domain model definitions for Anime4K Upscaler

import Foundation
import SwiftUI
import Observation
import Metal

// MARK: - Device Hardware Profile

struct DeviceHardwareProfile {
    let chipName: String
    let gpuName: String
    let cpuCoreCount: Int

    static let current: DeviceHardwareProfile = {
        let processInfo = ProcessInfo.processInfo
        let cpuCount = max(1, processInfo.activeProcessorCount)
        let gpu = MTLCreateSystemDefaultDevice()?.name ?? "Default GPU"

        var chip = "This Mac"
        var size: size_t = 0
        if sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 {
            var buffer = [CChar](repeating: 0, count: size)
            if sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 {
                chip = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if chip.isEmpty {
            chip = processInfo.hostName
        }

        return DeviceHardwareProfile(chipName: chip, gpuName: gpu, cpuCoreCount: cpuCount)
    }()

    var hqModeHeader: String {
        "HQ Modes (Recommended for \(chipName))"
    }
}

// MARK: - Anime4K Shader Files

/// Every individual GLSL shader file shipped with Anime4K.
/// Raw values are the exact filenames (without path).
enum Anime4KShader: String, CaseIterable, Identifiable, Sendable {
    case clampHighlights          = "Anime4K_Clamp_Highlights.glsl"
    case restoreCNN_VL            = "Anime4K_Restore_CNN_VL.glsl"
    case restoreCNN_M             = "Anime4K_Restore_CNN_M.glsl"
    case restoreCNN_S             = "Anime4K_Restore_CNN_S.glsl"
    case restoreCNNSoft_VL        = "Anime4K_Restore_CNN_Soft_VL.glsl"
    case restoreCNNSoft_M         = "Anime4K_Restore_CNN_Soft_M.glsl"
    case restoreCNNSoft_S         = "Anime4K_Restore_CNN_Soft_S.glsl"
    case upscaleCNN_x2_VL         = "Anime4K_Upscale_CNN_x2_VL.glsl"
    case upscaleCNN_x2_M          = "Anime4K_Upscale_CNN_x2_M.glsl"
    case upscaleCNN_x2_S          = "Anime4K_Upscale_CNN_x2_S.glsl"
    case upscaleDenoiseCNN_x2_VL  = "Anime4K_Upscale_Denoise_CNN_x2_VL.glsl"
    case upscaleDenoiseCNN_x2_M   = "Anime4K_Upscale_Denoise_CNN_x2_M.glsl"

    var id: String { rawValue }

    /// Whether this shader performs spatial upscaling (doubles resolution).
    var isUpscaler: Bool {
        switch self {
        case .upscaleCNN_x2_VL, .upscaleCNN_x2_M, .upscaleCNN_x2_S,
             .upscaleDenoiseCNN_x2_VL, .upscaleDenoiseCNN_x2_M:
            return true
        default:
            return false
        }
    }
}

// MARK: - Anime4K Processing Mode

/// The 15 Anime4K shader pipeline configurations.
/// Grouped into HQ (VL/M quality), Fast (M/S quality), and No-Upscale (restore-only).
enum Anime4KMode: Int, CaseIterable, Identifiable, Sendable {
    // HQ Modes (1–6)
    case modeA_HQ    = 1
    case modeB_HQ    = 2
    case modeC_HQ    = 3
    case modeAA_HQ   = 4
    case modeBB_HQ   = 5
    case modeCA_HQ   = 6
    // Fast Modes (7–12)
    case modeA_Fast   = 7
    case modeB_Fast   = 8
    case modeC_Fast   = 9
    case modeAA_Fast  = 10
    case modeBB_Fast  = 11
    case modeCA_Fast  = 12
    // No-Upscale Modes (13–15)
    case modeAA_Fast_NoUp = 13
    case modeA_HQ_NoUp    = 14
    case modeAA_HQ_NoUp   = 15

    var id: Int { rawValue }

    /// Human-readable display name.
    var displayName: String {
        switch self {
        case .modeA_HQ:         return "Mode A (HQ)"
        case .modeB_HQ:         return "Mode B (HQ)"
        case .modeC_HQ:         return "Mode C (HQ)"
        case .modeAA_HQ:        return "Mode A+A (HQ)"
        case .modeBB_HQ:        return "Mode B+B (HQ)"
        case .modeCA_HQ:        return "Mode C+A (HQ)"
        case .modeA_Fast:       return "Mode A (Fast)"
        case .modeB_Fast:       return "Mode B (Fast)"
        case .modeC_Fast:       return "Mode C (Fast)"
        case .modeAA_Fast:      return "Mode A+A (Fast)"
        case .modeBB_Fast:      return "Mode B+B (Fast)"
        case .modeCA_Fast:      return "Mode C+A (Fast)"
        case .modeAA_Fast_NoUp: return "Mode A+A (Fast) [No Upscale]"
        case .modeA_HQ_NoUp:    return "Mode A (HQ) [No Upscale]"
        case .modeAA_HQ_NoUp:   return "Mode A+A (HQ) [No Upscale]"
        }
    }

    /// Short description of what the mode does.
    var subtitle: String {
        switch self {
        case .modeA_HQ:         return "Restore → Upscale"
        case .modeB_HQ:         return "Soft Restore → Upscale"
        case .modeC_HQ:         return "Upscale + Denoise"
        case .modeAA_HQ:        return "Double Restore → Upscale"
        case .modeBB_HQ:        return "Double Soft → Upscale"
        case .modeCA_HQ:        return "Denoise → Restore → Upscale"
        case .modeA_Fast:       return "Restore → Upscale"
        case .modeB_Fast:       return "Soft Restore → Upscale"
        case .modeC_Fast:       return "Upscale + Denoise"
        case .modeAA_Fast:      return "Double Restore → Upscale"
        case .modeBB_Fast:      return "Double Soft → Upscale"
        case .modeCA_Fast:      return "Denoise → Restore → Upscale"
        case .modeAA_Fast_NoUp: return "Restore Only (Fast)"
        case .modeA_HQ_NoUp:    return "Restore Only (HQ)"
        case .modeAA_HQ_NoUp:   return "Double Restore Only (HQ)"
        }
    }

    /// Category grouping for sectioned UI display.
    var category: ModeCategory {
        switch self {
        case .modeA_HQ, .modeB_HQ, .modeC_HQ, .modeAA_HQ, .modeBB_HQ, .modeCA_HQ:
            return .hq
        case .modeA_Fast, .modeB_Fast, .modeC_Fast, .modeAA_Fast, .modeBB_Fast, .modeCA_Fast:
            return .fast
        case .modeAA_Fast_NoUp, .modeA_HQ_NoUp, .modeAA_HQ_NoUp:
            return .noUpscale
        }
    }

    /// Whether this mode involves spatial upscaling.
    var involvesUpscaling: Bool {
        category != .noUpscale
    }

    /// The ordered shader pipeline for this mode.
    /// Directly mapped from the reference shell script.
    var shaders: [Anime4KShader] {
        switch self {
        case .modeA_HQ:
            return [
                .clampHighlights,
                .restoreCNN_VL,
                .upscaleCNN_x2_VL,
                .upscaleCNN_x2_M
            ]
        case .modeB_HQ:
            return [
                .clampHighlights,
                .restoreCNNSoft_VL,
                .upscaleCNN_x2_VL,
                .upscaleCNN_x2_M
            ]
        case .modeC_HQ:
            return [
                .clampHighlights,
                .upscaleDenoiseCNN_x2_VL,
                .upscaleCNN_x2_M
            ]
        case .modeAA_HQ:
            return [
                .clampHighlights,
                .restoreCNN_VL,
                .upscaleCNN_x2_VL,
                .restoreCNN_M,
                .upscaleCNN_x2_M
            ]
        case .modeBB_HQ:
            return [
                .clampHighlights,
                .restoreCNNSoft_VL,
                .upscaleCNN_x2_VL,
                .restoreCNNSoft_M,
                .upscaleCNN_x2_M
            ]
        case .modeCA_HQ:
            return [
                .clampHighlights,
                .upscaleDenoiseCNN_x2_VL,
                .restoreCNN_M,
                .upscaleCNN_x2_M
            ]
        case .modeA_Fast:
            return [
                .clampHighlights,
                .restoreCNN_M,
                .upscaleCNN_x2_M,
                .upscaleCNN_x2_S
            ]
        case .modeB_Fast:
            return [
                .clampHighlights,
                .restoreCNNSoft_M,
                .upscaleCNN_x2_M,
                .upscaleCNN_x2_S
            ]
        case .modeC_Fast:
            return [
                .clampHighlights,
                .upscaleDenoiseCNN_x2_M,
                .upscaleCNN_x2_S
            ]
        case .modeAA_Fast:
            return [
                .clampHighlights,
                .restoreCNN_M,
                .upscaleCNN_x2_M,
                .restoreCNN_S,
                .upscaleCNN_x2_S
            ]
        case .modeBB_Fast:
            return [
                .clampHighlights,
                .restoreCNNSoft_M,
                .upscaleCNN_x2_M,
                .restoreCNNSoft_S,
                .upscaleCNN_x2_S
            ]
        case .modeCA_Fast:
            return [
                .clampHighlights,
                .upscaleDenoiseCNN_x2_M,
                .restoreCNN_S,
                .upscaleCNN_x2_S
            ]
        case .modeAA_Fast_NoUp:
            return [
                .clampHighlights,
                .restoreCNN_M,
                .restoreCNN_S
            ]
        case .modeA_HQ_NoUp:
            return [
                .clampHighlights,
                .restoreCNN_VL
            ]
        case .modeAA_HQ_NoUp:
            return [
                .clampHighlights,
                .restoreCNN_VL,
                .restoreCNN_M
            ]
        }
    }
}

// MARK: - Mode Category

/// Grouping for sectioned picker display.
enum ModeCategory: String, CaseIterable, Identifiable, Sendable {
    case hq        = "HQ Modes"
    case fast      = "Fast Modes"
    case noUpscale = "No Upscale Modes (Restore Only)"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hq:
            return DeviceHardwareProfile.current.hqModeHeader
        case .fast, .noUpscale:
            return rawValue
        }
    }

    /// The SF Symbol for each category's section header.
    var symbolName: String {
        switch self {
        case .hq:        return "star.fill"
        case .fast:      return "hare.fill"
        case .noUpscale: return "arrow.uturn.backward"
        }
    }

    /// All modes belonging to this category.
    var modes: [Anime4KMode] {
        Anime4KMode.allCases.filter { $0.category == self }
    }
}

// MARK: - Target Resolution

/// Output resolution scaling factor.
enum TargetResolution: Int, CaseIterable, Identifiable, Sendable {
    case keepOriginal = 1
    case double       = 2
    case quadruple    = 4

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .keepOriginal: return "Original (1x)"
        case .double:       return "2x Upscale"
        case .quadruple:    return "4x Upscale"
        }
    }

    var subtitle: String {
        switch self {
        case .keepOriginal: return "Keep original resolution"
        case .double:       return "e.g., 1080p → 4K"
        case .quadruple:    return "e.g., 1080p → 8K"
        }
    }

    /// SF Symbol name.
    var symbolName: String {
        switch self {
        case .keepOriginal: return "equal.square"
        case .double:       return "arrow.up.left.and.arrow.down.right"
        case .quadruple:    return "arrow.up.left.and.arrow.down.right.circle"
        }
    }

    /// The integer scale factor.
    var scaleFactor: Int { rawValue }
}

// MARK: - Video Codec

/// Supported output video encoders.
enum VideoCodec: String, CaseIterable, Identifiable, Sendable {
    case hevcVideoToolbox = "hevc_videotoolbox"
    case svtAV1           = "libsvtav1"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hevcVideoToolbox: return "HEVC (Hardware)"
        case .svtAV1:           return "AV1 (Software)"
        }
    }

    var subtitle: String {
        switch self {
        case .hevcVideoToolbox:
            return "VideoToolbox on \(DeviceHardwareProfile.current.gpuName) — Best speed & battery"
        case .svtAV1:
            return "SVT-AV1 on \(DeviceHardwareProfile.current.cpuCoreCount)-core CPU — Best compression"
        }
    }

    var symbolName: String {
        switch self {
        case .hevcVideoToolbox: return "bolt.fill"
        case .svtAV1:           return "cpu"
        }
    }

    /// The pixel format string for FFmpeg's format filter.
    var pixelFormat: String {
        switch self {
        case .hevcVideoToolbox: return "p010le"
        case .svtAV1:           return "yuv420p10le"
        }
    }

    /// Whether this codec uses CRF-based quality control (vs. -q:v).
    var usesCRF: Bool {
        self == .svtAV1
    }

    /// The FFmpeg encoder name string.
    var encoderName: String { rawValue }
}

// MARK: - Compression Mode

/// Video compression / quality control strategy.
enum CompressionMode: Identifiable, Sendable, Equatable {
    case visuallyLossless
    case balanced
    case customQuality(Int)
    case fixedBitrate(Int)

    var id: String {
        switch self {
        case .visuallyLossless:        return "visually_lossless"
        case .balanced:                return "balanced"
        case .customQuality(let v):    return "custom_q_\(v)"
        case .fixedBitrate(let v):     return "fixed_br_\(v)"
        }
    }

    var displayName: String {
        switch self {
        case .visuallyLossless:        return "Visually Lossless"
        case .balanced:                return "Balanced"
        case .customQuality(let v):    return "Custom Quality (\(v))"
        case .fixedBitrate(let v):     return "Fixed Bitrate (\(v) Mbps)"
        }
    }

    /// Returns the quality/CRF value for the given codec.
    /// For HEVC: -q:v value (0–100). For AV1: -crf value (0–63).
    func qualityValue(for codec: VideoCodec) -> Int {
        switch self {
        case .visuallyLossless:
            return codec.usesCRF ? 24 : 68
        case .balanced:
            return codec.usesCRF ? 30 : 65
        case .customQuality(let v):
            return v
        case .fixedBitrate:
            return 0 // Not used for bitrate mode
        }
    }

    /// Whether this mode uses fixed bitrate encoding.
    var isFixedBitrate: Bool {
        if case .fixedBitrate = self { return true }
        return false
    }

    /// Bitrate in Mbps (only valid for .fixedBitrate).
    var bitrateMbps: Int {
        if case .fixedBitrate(let v) = self { return v }
        return 0
    }

    /// Subtitle description for the compression UI, codec-aware.
    func subtitle(for codec: VideoCodec) -> String {
        switch self {
        case .visuallyLossless:
            return codec.usesCRF ? "CRF 24 (Recommended)" : "Quality 68 (Recommended)"
        case .balanced:
            return codec.usesCRF ? "CRF 30" : "Quality 65"
        case .customQuality(let v):
            return codec.usesCRF ? "CRF \(v)" : "Quality \(v)"
        case .fixedBitrate(let v):
            return "\(v) Mbps (Predictable file size)"
        }
    }

    static func == (lhs: CompressionMode, rhs: CompressionMode) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Compression Preset (for Picker binding)

/// A simplified picker-friendly enum that maps to CompressionMode.
/// Used in the UI where Picker requires a hashable, finite set.
enum CompressionPreset: String, CaseIterable, Identifiable, Sendable {
    case visuallyLossless = "visually_lossless"
    case balanced         = "balanced"
    case customQuality    = "custom_quality"
    case fixedBitrate     = "fixed_bitrate"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .visuallyLossless: return "Visually Lossless"
        case .balanced:         return "Balanced"
        case .customQuality:    return "Custom Quality"
        case .fixedBitrate:     return "Custom Bitrate"
        }
    }

    var symbolName: String {
        switch self {
        case .visuallyLossless: return "eye"
        case .balanced:         return "scalemass"
        case .customQuality:    return "slider.horizontal.3"
        case .fixedBitrate:     return "gauge.with.dots.needle.67percent"
        }
    }
}

// MARK: - Job State

/// Lifecycle state of a processing job.
enum JobState: String, Sendable {
    case idle       = "idle"
    case queued     = "queued"
    case running    = "running"
    case completed  = "completed"
    case failed     = "failed"
    case cancelled  = "cancelled"

    var displayName: String {
        switch self {
        case .idle:      return "Ready"
        case .queued:    return "Queued"
        case .running:   return "Processing"
        case .completed: return "Completed"
        case .failed:    return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    var symbolName: String {
        switch self {
        case .idle:      return "circle"
        case .queued:    return "clock"
        case .running:   return "circle.dashed"
        case .completed: return "checkmark.circle.fill"
        case .failed:    return "xmark.circle.fill"
        case .cancelled: return "stop.circle.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .idle:      return .secondary
        case .queued:    return .orange
        case .running:   return .blue
        case .completed: return .green
        case .failed:    return .red
        case .cancelled: return .yellow
        }
    }

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled: return true
        default: return false
        }
    }
}

// MARK: - Video File

/// Represents a single video file selected by the user.
struct VideoFile: Identifiable, Hashable, Sendable {
    let id: UUID
    let url: URL
    let fileName: String
    let fileExtension: String
    let fileSizeBytes: Int64
    var durationSeconds: Double?
    var width: Int?
    var height: Int?
    var bookmarkData: Data?

    init(url: URL) {
        self.id = UUID()
        self.url = url
        self.fileName = url.deletingPathExtension().lastPathComponent
        self.fileExtension = url.pathExtension.lowercased()
        self.bookmarkData = nil
        self.durationSeconds = nil
        self.width = nil
        self.height = nil

        let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey])
        self.fileSizeBytes = Int64(resourceValues?.fileSize ?? 0)
    }

    /// Formatted file size string (e.g. "1.23 GB").
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }

    /// Resolution string (e.g. "1920×1080") or nil.
    var resolutionString: String? {
        guard let w = width, let h = height else { return nil }
        return "\(w)×\(h)"
    }

    /// Formatted duration string (e.g. "01:23:45") or nil.
    var formattedDuration: String? {
        guard let dur = durationSeconds else { return nil }
        let hours = Int(dur) / 3600
        let minutes = (Int(dur) % 3600) / 60
        let seconds = Int(dur) % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    /// The output filename given a mode and scale factor.
    func outputFileName(mode: Anime4KMode, scale: TargetResolution) -> String {
        "\(fileName)_Mode\(mode.rawValue)_\(scale.scaleFactor)x.\(fileExtension)"
    }

    /// The output URL, using a specific output directory or the input file's directory.
    func outputURL(mode: Anime4KMode, scale: TargetResolution, outputDirectory: URL? = nil) -> URL {
        let baseDir = outputDirectory ?? url.deletingLastPathComponent()
        return baseDir.appendingPathComponent(outputFileName(mode: mode, scale: scale))
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: VideoFile, rhs: VideoFile) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Supported Video Extensions

/// File extensions accepted by the file picker and drag-drop zone.
enum SupportedVideoExtension: String, CaseIterable {
    case mp4  = "mp4"
    case mkv  = "mkv"
    case mov  = "mov"
    case avi  = "avi"
    case webm = "webm"
    case flv  = "flv"
    case ts   = "ts"

    /// All extensions as a Set for fast lookup.
    static let allExtensions: Set<String> = Set(allCases.map(\.rawValue))

    /// UTType identifiers for NSOpenPanel.
    static let utTypeIdentifiers: [String] = [
        "public.movie",
        "public.mpeg-4",
        "public.avi",
        "org.matroska.mkv",
        "com.apple.quicktime-movie",
        "org.webmproject.webm",
        "com.adobe.flash.video",
        "public.mpeg-2-transport-stream"
    ]
}

// MARK: - Job Configuration

/// Complete configuration for a processing run.
struct JobConfiguration: Sendable, Equatable {
    var mode: Anime4KMode
    var resolution: TargetResolution
    var codec: VideoCodec
    var compression: CompressionMode
    var longGOPEnabled: Bool

    /// Default configuration: Mode A (HQ), 2x, HEVC Hardware, Visually Lossless, Long GOP on.
    static let `default` = JobConfiguration(
        mode: .modeA_HQ,
        resolution: .double,
        codec: .hevcVideoToolbox,
        compression: .visuallyLossless,
        longGOPEnabled: true
    )

    static func == (lhs: JobConfiguration, rhs: JobConfiguration) -> Bool {
        lhs.mode == rhs.mode &&
        lhs.resolution == rhs.resolution &&
        lhs.codec == rhs.codec &&
        lhs.compression == rhs.compression &&
        lhs.longGOPEnabled == rhs.longGOPEnabled
    }
}

// MARK: - Processing Job

/// A single file being processed — tracks state, progress, and log output.
@MainActor @Observable
final class ProcessingJob: Identifiable {
    let id: UUID
    let file: VideoFile
    let configuration: JobConfiguration

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

    /// The Process handle for cancellation.
    @ObservationIgnored var processHandle: Process?

    init(file: VideoFile, configuration: JobConfiguration, outputDirectory: URL? = nil) {
        self.id = UUID()
        self.file = file
        self.configuration = configuration
        self.outputURL = file.outputURL(
            mode: configuration.mode,
            scale: configuration.resolution,
            outputDirectory: outputDirectory
        )
    }

    /// Elapsed time since processing started.
    var elapsedTime: TimeInterval? {
        guard let start = startDate else { return nil }
        let end = endDate ?? Date()
        return end.timeIntervalSince(start)
    }

    /// Formatted elapsed time string.
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

// MARK: - FFmpeg Progress Data

/// Parsed progress data from a single FFmpeg stderr status line.
struct FFmpegProgress: Sendable {
    let frame: Int
    let fps: Double
    let size: String
    let time: String
    let bitrate: String
    let speed: String

    /// Parse a time string "HH:MM:SS.ss" into total seconds.
    var timeSeconds: Double {
        let parts = time.split(separator: ":")
        guard parts.count == 3,
              let h = Double(parts[0]),
              let m = Double(parts[1]),
              let s = Double(parts[2]) else {
            return 0
        }
        return h * 3600 + m * 60 + s
    }

    /// Attempt to parse an FFmpeg stderr progress line.
    /// Example: "frame=  120 fps= 24 q=68.0 size=   12288kB time=00:00:05.00 bitrate=20132.4kbits/s speed=1.00x"
    static func parse(line: String) -> FFmpegProgress? {
        guard line.contains("frame="), line.contains("time=") else { return nil }

        // Direct key=value extraction via String.range(of:) — replaces 6
        // NSRegularExpression invocations with native Swift lookups.
        // Eliminates Obj-C bridging, NSTextCheckingResult heap allocations,
        // and ICU regex state-machine traversals on the ~30 Hz hot path.
        func extract(_ key: String, from s: String, default fallback: String = "") -> String {
            guard let r = s.range(of: key) else { return fallback }
            let after = s[r.upperBound...].drop(while: { $0.isWhitespace })
            let value = after.prefix(while: { !$0.isWhitespace })
            return value.isEmpty ? fallback : String(value)
        }

        let frameStr = extract("frame=", from: line, default: "0")
        let fpsStr = extract("fps=", from: line, default: "0")

        guard let frame = Int(frameStr),
              let fps = Double(fpsStr) else {
            return nil
        }

        return FFmpegProgress(
            frame: frame,
            fps: fps,
            size: extract("size=", from: line, default: "0kB"),
            time: extract("time=", from: line, default: "00:00:00.00"),
            bitrate: extract("bitrate=", from: line, default: "0kbits/s"),
            speed: extract("speed=", from: line, default: "0x")
        )
    }
}

// MARK: - Filter Graph Builder

/// Constructs the FFmpeg `-vf` filter string from a mode, resolution, and codec.
struct FilterGraphBuilder {

    /// Build the complete `-vf` filter value.
    /// - Parameters:
    ///   - mode: The Anime4K processing mode.
    ///   - resolution: Target output resolution scaling.
    ///   - codec: Video codec (determines pixel format).
    ///   - shaderDirectory: Absolute path to the directory containing .glsl files.
    /// - Returns: The assembled filter graph string for FFmpeg's `-vf` argument.
    static func build(
        mode: Anime4KMode,
        resolution: TargetResolution,
        codec: VideoCodec,
        shaderDirectory: String
    ) -> String {
        var filterComponents: [String] = []
        var currentScale = 1

        for shader in mode.shaders {
            let shaderPath = (shaderDirectory as NSString)
                .appendingPathComponent(shader.rawValue)
            // Escape single quotes in path for FFmpeg
            let escapedPath = shaderPath.replacingOccurrences(of: "'", with: "'\\''")

            if shader.isUpscaler {
                // Only apply upscaler if we haven't reached target scale
                if currentScale < resolution.scaleFactor {
                    filterComponents.append(
                        "libplacebo=w=iw*2:h=ih*2:custom_shader_path='\(escapedPath)'"
                    )
                    currentScale *= 2
                }
                // Skip upscaler if target scale already reached
            } else {
                filterComponents.append(
                    "libplacebo=custom_shader_path='\(escapedPath)'"
                )
            }
        }

        // Append pixel format conversion as the final filter
        filterComponents.append("format=\(codec.pixelFormat)")

        return filterComponents.joined(separator: ",")
    }
}

// MARK: - FFmpeg Argument Builder

/// Assembles the complete `[String]` argument array for an FFmpeg invocation.
struct FFmpegArgumentBuilder {

    /// Build the full FFmpeg arguments for a processing job.
    /// - Parameters:
    ///   - inputURL: The source video file URL.
    ///   - outputURL: The destination video file URL.
    ///   - configuration: The job configuration.
    ///   - shaderDirectory: Path to bundled shaders.
    /// - Returns: Array of argument strings (excluding the ffmpeg binary itself).
    static func build(
        inputURL: URL,
        outputURL: URL,
        configuration: JobConfiguration,
        shaderDirectory: String
    ) -> [String] {
        let filterGraph = FilterGraphBuilder.build(
            mode: configuration.mode,
            resolution: configuration.resolution,
            codec: configuration.codec,
            shaderDirectory: shaderDirectory
        )

        var args: [String] = []
        args.reserveCapacity(32) // ~28-32 args typical; avoids 3-4 backing-store reallocations

        // Overwrite output, input file
        args.append(contentsOf: ["-y"])
        args.append(contentsOf: ["-threads", "0"])
        args.append(contentsOf: ["-i", inputURL.path])

        // Let libplacebo initialize its device backend; explicit init can fail on some systems.

        // Video filter graph
        args.append(contentsOf: ["-vf", filterGraph])

        // Video codec
        args.append(contentsOf: ["-c:v", configuration.codec.encoderName])

        // Stream mapping: first video, all audio, all subtitles
        args.append(contentsOf: ["-map", "0:v:0"])
        args.append(contentsOf: ["-map", "0:a?"])
        args.append(contentsOf: ["-map", "0:s?"])

        // Copy audio and subtitle streams
        args.append(contentsOf: ["-c:a", "copy"])
        args.append(contentsOf: ["-c:s", "copy"])

        // Codec-specific encoding parameters
        switch configuration.codec {
        case .hevcVideoToolbox:
            args.append(contentsOf: [
                "-profile:v", "main10",
                "-prio_speed", "1",
                "-allow_sw", "1",
                "-bf", "7"
            ])

            if configuration.compression.isFixedBitrate {
                let mbps = configuration.compression.bitrateMbps
                let bRate = "\(mbps * 1000)k"
                let minRate = "\(Int(Double(mbps) * 900))k"
                let maxRate = "\(Int(Double(mbps) * 1100))k"
                let bufSize = "\(Int(Double(mbps) * 1500))k"
                args.append(contentsOf: [
                    "-b:v", bRate,
                    "-minrate", minRate,
                    "-maxrate", maxRate,
                    "-bufsize", bufSize
                ])
            } else {
                let qVal = configuration.compression.qualityValue(for: .hevcVideoToolbox)
                args.append(contentsOf: ["-q:v", "\(qVal)"])
            }

        case .svtAV1:
            args.append(contentsOf: [
                "-preset", "6",
                "-svtav1-params", "tune=0"
            ])

            if configuration.compression.isFixedBitrate {
                let mbps = configuration.compression.bitrateMbps
                let bRate = "\(mbps * 1000)k"
                let maxRate = "\(Int(Double(mbps) * 1100))k"
                let bufSize = "\(Int(Double(mbps) * 1500))k"
                args.append(contentsOf: [
                    "-b:v", bRate,
                    "-maxrate", maxRate,
                    "-bufsize", bufSize
                ])
            } else {
                let crfVal = configuration.compression.qualityValue(for: .svtAV1)
                args.append(contentsOf: ["-crf", "\(crfVal)"])
            }
        }

        // Long GOP (10 seconds at ~24fps)
        if configuration.longGOPEnabled {
            args.append(contentsOf: ["-g", "240"])
        }

        // Progress output for parsing
        args.append(contentsOf: ["-progress", "pipe:1"])

        // Output file
        args.append(outputURL.path)

        return args
    }
}
