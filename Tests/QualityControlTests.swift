// Tests/QualityControlTests.swift
// Unit test for Quality/CRF/Bitrate control and argument emission across all three tabs.

import Foundation

// MARK: - Quality & Encoding Argument Spec

struct QualityArgSpec {
    static func buildUpscaleCompressionArgs(codec: String, usesCRF: Bool, qualityVal: Int, isBitrate: Bool, bitrateMbps: Int, svtPreset: Int, longGOP: Bool) -> [String] {
        var args: [String] = []
        if codec == "hevc_videotoolbox" {
            args.append(contentsOf: [
                "-profile:v", "main10",
                "-prio_speed", "1",
                "-allow_sw", "1",
                "-bf", "7"
            ])
            if isBitrate {
                let mbps = bitrateMbps
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
                args.append(contentsOf: ["-q:v", "\(qualityVal)"])
            }
        } else if codec == "libsvtav1" {
            args.append(contentsOf: [
                "-preset", "\(svtPreset)",
                "-svtav1-params", "tune=0"
            ])
            if isBitrate {
                let mbps = bitrateMbps
                let bRate = "\(mbps * 1000)k"
                let maxRate = "\(Int(Double(mbps) * 1100))k"
                let bufSize = "\(Int(Double(mbps) * 1500))k"
                args.append(contentsOf: [
                    "-b:v", bRate,
                    "-maxrate", maxRate,
                    "-bufsize", bufSize
                ])
            } else {
                args.append(contentsOf: ["-crf", "\(qualityVal)"])
            }
        }
        if longGOP {
            args.append(contentsOf: ["-g", "240"])
        }
        return args
    }

    static func buildRealESRGANEncodeArgs(fps: String, codec: String, pixFmt: String, inPath: String, outPath: String, framesPath: String, compArgs: [String]) -> [String] {
        var enc = ["-y", "-progress", "pipe:1", "-r", fps,
                   "-i", framesPath,
                   "-i", inPath,
                   "-map", "0:v:0", "-map", "1:a?", "-map", "1:s?",
                   "-c:a", "copy", "-c:s", "copy",
                   "-c:v", codec,
                   "-pix_fmt", pixFmt]
        enc.append(contentsOf: compArgs)
        enc.append(outPath)
        return enc
    }
}

@main
struct QualityControlTests {
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

        // Test 1: HEVC Visually Lossless default
        let hevcDefaultArgs = QualityArgSpec.buildUpscaleCompressionArgs(
            codec: "hevc_videotoolbox", usesCRF: false, qualityVal: 68,
            isBitrate: false, bitrateMbps: 0, svtPreset: 6, longGOP: true
        )
        check("HEVC default has -q:v 68", hevcDefaultArgs.contains("-q:v") && hevcDefaultArgs[hevcDefaultArgs.firstIndex(of: "-q:v")! + 1] == "68")
        check("HEVC default has -profile:v main10", hevcDefaultArgs.contains("-profile:v") && hevcDefaultArgs[hevcDefaultArgs.firstIndex(of: "-profile:v")! + 1] == "main10")
        check("HEVC default has -bf 7", hevcDefaultArgs.contains("-bf") && hevcDefaultArgs[hevcDefaultArgs.firstIndex(of: "-bf")! + 1] == "7")
        check("HEVC default has -g 240", hevcDefaultArgs.contains("-g") && hevcDefaultArgs[hevcDefaultArgs.firstIndex(of: "-g")! + 1] == "240")

        // Test 2: AV1 Visually Lossless default
        let av1DefaultArgs = QualityArgSpec.buildUpscaleCompressionArgs(
            codec: "libsvtav1", usesCRF: true, qualityVal: 24,
            isBitrate: false, bitrateMbps: 0, svtPreset: 6, longGOP: true
        )
        check("AV1 default has -crf 24", av1DefaultArgs.contains("-crf") && av1DefaultArgs[av1DefaultArgs.firstIndex(of: "-crf")! + 1] == "24")
        check("AV1 default has -preset 6", av1DefaultArgs.contains("-preset") && av1DefaultArgs[av1DefaultArgs.firstIndex(of: "-preset")! + 1] == "6")
        check("AV1 default has -svtav1-params tune=0", av1DefaultArgs.contains("-svtav1-params") && av1DefaultArgs[av1DefaultArgs.firstIndex(of: "-svtav1-params")! + 1] == "tune=0")
        check("AV1 default has -g 240", av1DefaultArgs.contains("-g") && av1DefaultArgs[av1DefaultArgs.firstIndex(of: "-g")! + 1] == "240")

        // Test 3: AV1 Custom Quality (e.g. CRF 18, Preset 4)
        let av1CustomArgs = QualityArgSpec.buildUpscaleCompressionArgs(
            codec: "libsvtav1", usesCRF: true, qualityVal: 18,
            isBitrate: false, bitrateMbps: 0, svtPreset: 4, longGOP: false
        )
        check("AV1 custom has -crf 18", av1CustomArgs.contains("-crf") && av1CustomArgs[av1CustomArgs.firstIndex(of: "-crf")! + 1] == "18")
        check("AV1 custom has -preset 4", av1CustomArgs.contains("-preset") && av1CustomArgs[av1CustomArgs.firstIndex(of: "-preset")! + 1] == "4")
        check("AV1 custom without long GOP lacks -g", !av1CustomArgs.contains("-g"))

        // Test 4: HEVC Fixed Bitrate (50 Mbps)
        let hevcBitrateArgs = QualityArgSpec.buildUpscaleCompressionArgs(
            codec: "hevc_videotoolbox", usesCRF: false, qualityVal: 0,
            isBitrate: true, bitrateMbps: 50, svtPreset: 6, longGOP: true
        )
        check("HEVC bitrate has -b:v 50000k", hevcBitrateArgs.contains("-b:v") && hevcBitrateArgs[hevcBitrateArgs.firstIndex(of: "-b:v")! + 1] == "50000k")
        check("HEVC bitrate has -maxrate 55000k", hevcBitrateArgs.contains("-maxrate") && hevcBitrateArgs[hevcBitrateArgs.firstIndex(of: "-maxrate")! + 1] == "55000k")
        check("HEVC bitrate lacks -q:v", !hevcBitrateArgs.contains("-q:v"))

        // Test 5: Real-ESRGAN Final Stage Command Includes Compression Args
        let realESRGANArgs = QualityArgSpec.buildRealESRGANEncodeArgs(
            fps: "24.000",
            codec: "libsvtav1",
            pixFmt: "yuv420p10le",
            inPath: "/tmp/in.mp4",
            outPath: "/tmp/out.mp4",
            framesPath: "/tmp/frames/%08d.png",
            compArgs: av1CustomArgs
        )
        check("Real-ESRGAN includes -crf 18", realESRGANArgs.contains("-crf") && realESRGANArgs[realESRGANArgs.firstIndex(of: "-crf")! + 1] == "18")
        check("Real-ESRGAN includes -preset 4", realESRGANArgs.contains("-preset") && realESRGANArgs[realESRGANArgs.firstIndex(of: "-preset")! + 1] == "4")
        check("Real-ESRGAN output is last argument", realESRGANArgs.last == "/tmp/out.mp4")

        print("\n\(passed) passed, \(failed) failed\n")
        if failed > 0 { exit(1) }
    }
}
