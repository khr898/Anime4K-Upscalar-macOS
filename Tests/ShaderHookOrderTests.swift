// Tests/ShaderHookOrderTests.swift
// Unit test to verify shader hook declarations and ensure Anime4K_Clamp_Highlights.glsl
// uses //!HOOK MAIN exclusively to prevent libplacebo out-of-order execution artifacts.

import Foundation

enum Anime4KShader: String {
    case clampHighlights = "Anime4K_Clamp_Highlights.glsl"
    case restoreCNNM = "Anime4K_Restore_CNN_M.glsl"
    case upscaleCNNx2M = "Anime4K_Upscale_CNN_x2_M.glsl"
}

@main
struct ShaderHookOrderTests {
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

        let shadersDir = "Anime4K-Upscaler/Resources/Shaders"
        let fm = FileManager.default

        guard let shaderFiles = try? fm.contentsOfDirectory(atPath: shadersDir) else {
            print("FAIL: Could not list shaders in \(shadersDir)")
            exit(1)
        }

        let glslFiles = shaderFiles.filter { $0.hasSuffix(".glsl") }
        check("found shader files", !glslFiles.isEmpty, "Found 0 glsl files")

        // 1. Specifically verify Anime4K_Clamp_Highlights.glsl
        let clampPath = "\(shadersDir)/Anime4K_Clamp_Highlights.glsl"
        if let clampContent = try? String(contentsOfFile: clampPath, encoding: .utf8) {
            let hasPrekernel = clampContent.contains("//!HOOK PREKERNEL")
            check("Anime4K_Clamp_Highlights does NOT contain //!HOOK PREKERNEL", !hasPrekernel, "Found //!HOOK PREKERNEL in clamp highlights")

            let mainHooks = clampContent.components(separatedBy: "//!HOOK MAIN").count - 1
            check("Anime4K_Clamp_Highlights has 3 //!HOOK MAIN passes", mainHooks == 3, "Expected 3 //!HOOK MAIN, found \(mainHooks)")
        } else {
            check("Anime4K_Clamp_Highlights.glsl readable", false, "File missing or unreadable")
        }

        // 2. Scan all shaders: ensure every pass hooks into MAIN
        for file in glslFiles {
            let path = "\(shadersDir)/\(file)"
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
                check("\(file) readable", false)
                continue
            }

            let lines = content.components(separatedBy: .newlines)
            for (idx, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//!HOOK") {
                    let hookTarget = trimmed.replacingOccurrences(of: "//!HOOK", with: "").trimmingCharacters(in: .whitespaces)
                    check("\(file):\(idx + 1) hook target is MAIN", hookTarget == "MAIN", "Found hook '\(hookTarget)' in \(file)")
                }
            }
        }

        // 3. Verify ShaderCombiner texture namespace isolation
        let clampShader = "\(shadersDir)/Anime4K_Clamp_Highlights.glsl"
        let restoreShader = "\(shadersDir)/Anime4K_Restore_CNN_M.glsl"
        let upscaleShader = "\(shadersDir)/Anime4K_Upscale_CNN_x2_M.glsl"

        if let clampC = try? String(contentsOfFile: clampShader, encoding: .utf8),
           let restoreC = try? String(contentsOfFile: restoreShader, encoding: .utf8),
           let upscaleC = try? String(contentsOfFile: upscaleShader, encoding: .utf8) {

            let s0 = ShaderCombiner.isolateShaderTextures(content: clampC, prefix: "s0_")
            let s1 = ShaderCombiner.isolateShaderTextures(content: restoreC, prefix: "s1_")
            let s2 = ShaderCombiner.isolateShaderTextures(content: upscaleC, prefix: "s2_")
            let combined = s0 + "\n\n" + s1 + "\n\n" + s2

            check("s0 prefixed STATSMAX", s0.contains("//!SAVE s0_STATSMAX"))
            check("s1 prefixed conv2d_tf", s1.contains("//!SAVE s1_conv2d_tf"))
            check("s2 prefixed conv2d_tf", s2.contains("//!SAVE s2_conv2d_tf"))
            check("s1 and s2 do not share conv2d_tf", !combined.contains("//!SAVE conv2d_tf"))
            check("MAIN is not prefixed in s0", s0.contains("//!HOOK MAIN"))
            check("MAIN is not prefixed in s1", s1.contains("//!SAVE MAIN"))
            check("MAIN is not prefixed in s2", s2.contains("//!SAVE MAIN"))
            check("s1 properly prefixes _pos", s1.contains("s1_conv2d_tf_pos") && !s1.contains(" conv2d_tf_pos"))
            check("s2 properly prefixes _pos", s2.contains("s2_conv2d_tf_pos") && !s2.contains(" conv2d_tf_pos"))
        } else {
            check("Failed to load shaders for isolation test", false)
        }

        print("\n\(passed) passed, \(failed) failed\n")
        if failed > 0 { exit(1) }
    }
}
