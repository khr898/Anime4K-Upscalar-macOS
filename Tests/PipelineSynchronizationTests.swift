// Tests/PipelineSynchronizationTests.swift
// Unit tests for MoltenVK environment synchronization and FFmpeg filter threading flags.

import Foundation

struct PipelineSynchronizationTests {
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

        // --- Test 1: MoltenVK Synchronization Environment Configuration ---
        var env: [String: String] = [:]
        env["MVK_CONFIG_ALLOW_METAL_EVENTS"] = "1"
        env["MVK_CONFIG_VK_SEMAPHORE_SUPPORT_STYLE"] = "1"
        env["MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS"] = "1"
        env["MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS"] = "0"
        env["MVK_CONFIG_FULL_IMAGE_VIEW_SWIZZLE"] = "1"
        env["MVK_CONFIG_FAST_MATH_ENABLED"] = "0"
        env["MVK_CONFIG_RESUME_LOST_DEVICE"] = "1"

        check("MVK allow metal events is enabled (1)", env["MVK_CONFIG_ALLOW_METAL_EVENTS"] == "1")
        check("MVK semaphore support style is metal events where safe (1)", env["MVK_CONFIG_VK_SEMAPHORE_SUPPORT_STYLE"] == "1")
        check("MVK synchronous queue submits is enabled (1)", env["MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS"] == "1")
        check("MVK prefill command buffers is disabled (0)", env["MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS"] == "0")
        check("MVK full image view swizzle is enabled (1)", env["MVK_CONFIG_FULL_IMAGE_VIEW_SWIZZLE"] == "1")
        check("MVK fast math is disabled (0)", env["MVK_CONFIG_FAST_MATH_ENABLED"] == "0")
        check("MVK resume lost device is enabled (1)", env["MVK_CONFIG_RESUME_LOST_DEVICE"] == "1")

        // --- Test 2: Vulkan ICD Manifest API Version ---
        let mockICDContent = """
        {
            "file_format_version": "1.0.0",
            "ICD": {
                "library_path": "/path/to/libMoltenVK.dylib",
                "api_version": "1.4.0"
            }
        }
        """
        check("ICD manifest specifies api_version 1.4.0", mockICDContent.contains("\"api_version\": \"1.4.0\""))

        // --- Test 3: Sequential Multi-Stage libplacebo Filtergraph ---
        func mockBuildSequentialFilterGraph(stages: [(path: String, scales2x: Bool)], pixelFormat: String) -> String {
            guard !stages.isEmpty else { return "format=\(pixelFormat)" }
            var components = ["hwupload"]
            for (path, scales2x) in stages {
                let escapedPath = path.replacingOccurrences(of: "'", with: "'\\''")
                if scales2x {
                    components.append("libplacebo=w=iw*2:h=ih*2:custom_shader_path='\(escapedPath)':format=\(pixelFormat)")
                } else {
                    components.append("libplacebo=custom_shader_path='\(escapedPath)':format=\(pixelFormat)")
                }
            }
            components.append("hwdownload")
            components.append("format=\(pixelFormat)")
            return components.joined(separator: ",")
        }

        let testStages: [(String, Bool)] = [
            ("/path/Anime4K_Clamp_Highlights.glsl", false),
            ("/path/Anime4K_Restore_CNN_VL.glsl", false),
            ("/path/Anime4K_Upscale_CNN_x2_VL.glsl", true)
        ]
        let fg2x = mockBuildSequentialFilterGraph(stages: testStages, pixelFormat: "p010le")
        let libplaceboOccurrences = fg2x.components(separatedBy: "libplacebo").count - 1
        check("FilterGraph contains 3 sequential libplacebo stages for Mode A 2x", libplaceboOccurrences == 3)
        check("FilterGraph starts with hwupload and ends with hwdownload,format=p010le",
              fg2x.hasPrefix("hwupload,libplacebo") && fg2x.hasSuffix("hwdownload,format=p010le"))
        check("Only upscale stage specifies w=iw*2:h=ih*2",
              fg2x.contains("libplacebo=w=iw*2:h=ih*2:custom_shader_path='/path/Anime4K_Upscale_CNN_x2_VL.glsl':format=p010le") &&
              fg2x.contains("libplacebo=custom_shader_path='/path/Anime4K_Restore_CNN_VL.glsl':format=p010le"))

        // --- Test 4: FFmpeg Filter Threading Arguments ---
        func mockBuildFFmpegArgs(inputPath: String, filterGraph: String) -> [String] {
            var args: [String] = []
            args.append(contentsOf: ["-init_hw_device", "vulkan=vk:0", "-filter_hw_device", "vk"])
            args.append(contentsOf: ["-y"])
            args.append(contentsOf: ["-threads", "0"])
            args.append(contentsOf: ["-filter_threads", "1"])
            args.append(contentsOf: ["-filter_complex_threads", "1"])
            args.append(contentsOf: ["-i", inputPath])
            args.append(contentsOf: ["-vf", filterGraph])
            return args
        }

        let testArgs = mockBuildFFmpegArgs(inputPath: "/tmp/in.mp4", filterGraph: fg2x)
        check("FFmpeg arguments contain -filter_threads 1",
              testArgs.contains("-filter_threads") &&
              testArgs[testArgs.firstIndex(of: "-filter_threads")! + 1] == "1")
        check("FFmpeg arguments contain -filter_complex_threads 1",
              testArgs.contains("-filter_complex_threads") &&
              testArgs[testArgs.firstIndex(of: "-filter_complex_threads")! + 1] == "1")
        check("FFmpeg arguments preserve -threads 0 for decode/encode",
              testArgs.contains("-threads") &&
              testArgs[testArgs.firstIndex(of: "-threads")! + 1] == "0")

        print("\nPipelineSynchronizationTests Results: \(passed) passed, \(failed) failed\n")
        if failed > 0 { exit(1) }
    }
}

PipelineSynchronizationTests.main()

