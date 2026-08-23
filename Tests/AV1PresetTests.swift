// Tests/AV1PresetTests.swift
// Pure-Foundation unit test for SVT-AV1 preset handling, range validation, and argument generation.

import Foundation

enum TestSVTAV1 {
    static func buildCompressArgs(preset: Int, crf: Int, hdr10: Bool) -> [String] {
        var args = ["-hide_banner", "-v", "error", "-stats", "-y", "-i", "/tmp/in.mkv", "-map", "0:v:0", "-map", "0:a?", "-map", "0:s?", "-c:a", "copy", "-c:s", "copy"]
        var svtParams = "tune=0:"
        if hdr10 {
            svtParams += "enable-hdr=1:"
        } else {
            svtParams += "enable-hdr=0:color-primaries=1:transfer-characteristics=1:matrix-coefficients=1:range=1:"
        }
        svtParams = String(svtParams.dropLast())
        args.append(contentsOf: [
            "-c:v", "libsvtav1",
            "-preset", "\(preset)",
            "-crf", "\(crf)",
            "-pix_fmt", "yuv420p10le",
            "-svtav1-params", svtParams
        ])
        return args
    }

    static func buildStreamOptimizeArgs(preset: Int, crf: Int, pixFmt: String = "yuv420p10le", faststart: Bool = true) -> [String] {
        var args = ["-nostdin", "-hide_banner", "-v", "error", "-stats", "-y", "-i", "/tmp/in.mkv", "-map", "0:v:0", "-map", "0:a?", "-map", "0:s?"]
        args.append(contentsOf: [
            "-c:v", "libsvtav1",
            "-preset", "\(preset)",
            "-crf", "\(crf)",
            "-pix_fmt", pixFmt,
            "-svtav1-params", "tune=0"
        ])
        args.append(contentsOf: ["-force_key_frames", "expr:gte(t,n_forced*2)"])
        args.append(contentsOf: ["-c:a", "copy"])
        args.append(contentsOf: ["-c:s", "mov_text"])
        if faststart {
            args.append(contentsOf: ["-movflags", "+faststart"])
        }
        args.append("/tmp/out.mp4")
        return args
    }

    static func presetDescription(_ preset: Int) -> String {
        switch preset {
        case 0...3:
            return "Archival (Slowest, Maximum Compression)"
        case 4...6:
            return "Standard (Balanced Speed & Quality - Recommended)"
        case 7...10:
            return "Fast (High Speed, Moderate Compression)"
        case 11...13:
            return "Real-time (Ultra Fast, Lower Compression)"
        default:
            return ""
        }
    }
}

@main
struct AV1PresetTests {
    static func main() {
        var passed = 0
        var failed = 0

        func check(_ name: String, _ condition: Bool, _ detail: String = "") {
            if condition {
                print("PASS: \(name)")
                passed += 1
            } else {
                print("FAIL: \(name) \(detail)")
                failed += 1
            }
        }

        // Test presets 0 through 13
        for preset in 0...13 {
            let desc = TestSVTAV1.presetDescription(preset)
            check("Preset \(preset) has non-empty description", !desc.isEmpty)

            let compArgs = TestSVTAV1.buildCompressArgs(preset: preset, crf: 24, hdr10: false)
            if let pIdx = compArgs.firstIndex(of: "-preset") {
                check("Compress preset \(preset) matched in args", compArgs[pIdx + 1] == "\(preset)")
            } else {
                check("Compress preset \(preset) in args", false)
            }

            let streamArgs = TestSVTAV1.buildStreamOptimizeArgs(preset: preset, crf: 28)
            if let pIdx = streamArgs.firstIndex(of: "-preset") {
                check("StreamOptimize preset \(preset) matched in args", streamArgs[pIdx + 1] == "\(preset)")
            } else {
                check("StreamOptimize preset \(preset) in args", false)
            }
        }

        // Test description category boundaries
        check("Preset 0 is Archival", TestSVTAV1.presetDescription(0).contains("Archival"))
        check("Preset 3 is Archival", TestSVTAV1.presetDescription(3).contains("Archival"))
        check("Preset 4 is Standard", TestSVTAV1.presetDescription(4).contains("Standard"))
        check("Preset 6 is Standard", TestSVTAV1.presetDescription(6).contains("Standard"))
        check("Preset 7 is Fast", TestSVTAV1.presetDescription(7).contains("Fast"))
        check("Preset 10 is Fast", TestSVTAV1.presetDescription(10).contains("Fast"))
        check("Preset 11 is Real-time", TestSVTAV1.presetDescription(11).contains("Real-time"))
        check("Preset 13 is Real-time", TestSVTAV1.presetDescription(13).contains("Real-time"))

        print("\n\(passed) passed, \(failed) failed\n")
        if failed > 0 { exit(1) }
    }
}
