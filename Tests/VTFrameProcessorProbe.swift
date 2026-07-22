// Tests/VTFrameProcessorProbe.swift
// Phase 0 probe — determine if Apple's native VTFrameProcessor neural SR is
// usable at 1080p on this machine before investing in the CoreML rebuild.
//
// Standalone swiftc-compiled probe (matches existing Tests/ convention: no
// Swift Testing / SPM dependency, runnable anywhere swiftc is).
//
// Build + run:
//   swiftc Tests/VTFrameProcessorProbe.swift -o /tmp/vtprobe \
//         -target arm64-apple-macos26.0 \
//         -framework VideoToolbox -framework CoreMedia -framework Foundation \
//   && /tmp/vtprobe
//
// SDK headers (VTFrameProcessor_SuperResolutionScaler.h,
// VTFrameProcessor_LowLatencySuperResolutionScaler.h) declare both
// configurations API_AVAILABLE(macos(26.0)) — not 15.4 as the plan stated.
// Machine is Darwin 25.5 = macOS 26 Tahoe, so the API is present.

import Foundation
import VideoToolbox
import CoreMedia

@main
struct VTFrameProcessorProbe {
    static func main() {
        var lines: [String] = []
        func line(_ s: String) { lines.append(s) }

        line("=== VTFrameProcessor SR Probe ===")
        line("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")

        // Both configurations are macOS 26.0+. Guard once.
        if #available(macOS 26.0, *) {
            probeHighQuality(line: line)
            line("")
            probeLowLatency(line: line)
        } else {
            line("macOS < 26.0: VTFrameProcessor SR configurations unavailable.")
        }

        let out = lines.joined(separator: "\n")
        print(out)
        // Also dump to stdout is enough; caller tees to plan evidence file.
    }

    @available(macOS 26.0, *)
    static func probeHighQuality(line: (String) -> Void) {
        line("")
        line("--- VTSuperResolutionScalerConfiguration (high-quality) ---")
        let supported = VTSuperResolutionScalerConfiguration.isSupported
        line("isSupported: \(supported)")
        let scaleFactors = VTSuperResolutionScalerConfiguration.supportedScaleFactors
        line("supportedScaleFactors (class-level): \(scaleFactors)")
        let revisions = VTSuperResolutionScalerConfiguration.supportedRevisions
        line("supportedRevisions: \(revisions)")
        line("defaultRevision: \(VTSuperResolutionScalerConfiguration.defaultRevision.rawValue)")

        // The init returns nil when dimensions are out of range. Probe which
        // (width,height,scaleFactor,inputType) combos are accepted at 1080p and 720p.
        // Header docs: video input max 1920x1080 on macOS.
        let combos: [(Int, Int, Int, VTSuperResolutionScalerConfiguration.InputType)] = [
            (1920, 1080, 2, .video),
            (1920, 1080, 4, .video),
            (1280, 720, 2, .video),
            (1280, 720, 4, .video),
            (640, 480, 2, .video),
            (1920, 1080, 2, .image),
        ]
        for (w, h, s, t) in combos {
            let cfg = VTSuperResolutionScalerConfiguration(
                frameWidth: w,
                frameHeight: h,
                scaleFactor: s,
                inputType: t,
                usePrecomputedFlow: false,
                qualityPrioritization: .normal,
                revision: .revision1
            )
            let status = cfg?.configurationModelStatus.rawValue ?? -1
            line("init(w=\(w) h=\(h) scale=\(s) type=\(t)): \(cfg != nil ? "OK" : "nil") modelStatus=\(status)")
        }
    }

    @available(macOS 26.0, *)
    static func probeLowLatency(line: (String) -> Void) {
        line("")
        line("--- VTLowLatencySuperResolutionScalerConfiguration (low-latency) ---")
        let supported = VTLowLatencySuperResolutionScalerConfiguration.isSupported
        line("isSupported: \(supported)")
        let maxD = VTLowLatencySuperResolutionScalerConfiguration.maximumDimensions
        let minD = VTLowLatencySuperResolutionScalerConfiguration.minimumDimensions
        if let m = maxD { line("maximumDimensions: \(m.width)x\(m.height)") } else { line("maximumDimensions: nil") }
        if let m = minD { line("minimumDimensions: \(m.width)x\(m.height)") } else { line("minimumDimensions: nil") }

        let dims: [(Int, Int)] = [(1920, 1080), (1280, 720), (640, 480)]
        for (w, h) in dims {
            let factors = VTLowLatencySuperResolutionScalerConfiguration
                .supportedScaleFactors(frameWidth: w, frameHeight: h)
            line("supportedScaleFactors(w=\(w) h=\(h)): \(factors)")
        }
    }
}