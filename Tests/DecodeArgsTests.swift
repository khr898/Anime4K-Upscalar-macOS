// Tests/DecodeArgsTests.swift
// Standalone assert-based self-check for the streaming-decode argument builder
// used by the Special (Core ML / ANE) preset pipeline. Three decode modes:
// VideoToolbox hardware, libdav1d software fallback, and default (no override).
// Compile + run outside Xcode:
//   swiftc Anime4K-Upscaler/Utilities/FrameAccumulator.swift \
//          Anime4K-Upscaler/Utilities/RawVideoFrameSource.swift \
//          Tests/DecodeArgsTests.swift -o /tmp/dargs && /tmp/dargs
//
// These args are what the app launches ffmpeg with to stream decoded BGRA
// frames into the Core ML upscale loop. AV1 sources require either
// -hwaccel videotoolbox (Apple Silicon with AV1 VT decode) or -c:v libdav1d
// (software fallback for unsupported devices); the native `av1` decoder
// selected by the default args is hardware-only and fails on devices without
// a functioning AV1 hwaccel, so the builder must emit the override modes.

import Foundation
import CoreVideo

@main
struct DecodeArgsTests {
    static func main() {
        var passed = 0
        var failed = 0

        func check(_ name: String, _ condition: Bool, _ detail: String = "") {
            if condition { print("PASS: \(name)"); passed += 1 }
            else { print("FAIL: \(name) \(detail)"); failed += 1 }
        }

        let input = "/tmp/clip.mkv"
        let shader = "/app/Shaders/Anime4K_Restore_CNN_VL.glsl"

        // --- Non-SDRescue (plain decode) ---
        do {
            let a = RawVideoFrameSource.streamArgs(mode: .default, inputPath: input,
                                                    isSDRescue: false, shaderPath: shader)
            check("plain default", a == ["-y", "-i", input, "-pix_fmt", "bgra", "-f", "rawvideo", "pipe:1"], "got \(a)")
        }
        do {
            let a = RawVideoFrameSource.streamArgs(mode: .videoToolbox, inputPath: input,
                                                    isSDRescue: false, shaderPath: shader)
            check("plain videoToolbox has -hwaccel videotoolbox before -i",
                  a == ["-y", "-hwaccel", "videotoolbox", "-i", input, "-pix_fmt", "bgra", "-f", "rawvideo", "pipe:1"],
                  "got \(a)")
        }
        do {
            let a = RawVideoFrameSource.streamArgs(mode: .softwareDav1d, inputPath: input,
                                                    isSDRescue: false, shaderPath: shader)
            check("plain softwareDav1d forces libdav1d decoder before -i",
                  a == ["-y", "-c:v", "libdav1d", "-i", input, "-pix_fmt", "bgra", "-f", "rawvideo", "pipe:1"],
                  "got \(a)")
        }

        // --- SDRescue (Vulkan libplacebo Restore VL chain) ---
        let sdrVF = "hwupload,libplacebo=custom_shader_path=\(shader):format=p010le,hwdownload,format=p010le"
        do {
            let a = RawVideoFrameSource.streamArgs(mode: .default, inputPath: input,
                                                    isSDRescue: true, shaderPath: shader)
            check("sdr default chain",
                  a == ["-init_hw_device", "vulkan=vk:0", "-filter_hw_device", "vk", "-y",
                        "-i", input, "-vf", sdrVF, "-pix_fmt", "bgra", "-f", "rawvideo", "pipe:1"],
                  "got \(a)")
        }
        do {
            // VT hwaccel is NOT applied to the SDRescue Vulkan chain (unverified
            // VT+Vulkan interaction); .videoToolbox collapses to .default here.
            let a = RawVideoFrameSource.streamArgs(mode: .videoToolbox, inputPath: input,
                                                    isSDRescue: true, shaderPath: shader)
            check("sdr videoToolbox collapses to default (no -hwaccel on Vulkan chain)",
                  !a.contains("-hwaccel") && a.contains("-vf") && a.contains(sdrVF),
                  "got \(a)")
        }
        do {
            let a = RawVideoFrameSource.streamArgs(mode: .softwareDav1d, inputPath: input,
                                                    isSDRescue: true, shaderPath: shader)
            check("sdr softwareDav1d forces libdav1d decoder before -i",
                  a == ["-init_hw_device", "vulkan=vk:0", "-filter_hw_device", "vk", "-y",
                        "-c:v", "libdav1d", "-i", input, "-vf", sdrVF, "-pix_fmt", "bgra",
                        "-f", "rawvideo", "pipe:1"],
                  "got \(a)")
        }

        print("\n\(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}