// Tests/ShaderHookOrderTests.swift
// Unit test to verify shader integrity and validate that all 12 bundled Anime4K GLSL shaders
// are present, valid, and contain required //!HOOK and //!DESC directives.

import Foundation

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

        let expectedShaders: [String] = [
            "Anime4K_Clamp_Highlights.glsl",
            "Anime4K_Restore_CNN_VL.glsl",
            "Anime4K_Restore_CNN_M.glsl",
            "Anime4K_Restore_CNN_S.glsl",
            "Anime4K_Restore_CNN_Soft_VL.glsl",
            "Anime4K_Restore_CNN_Soft_M.glsl",
            "Anime4K_Restore_CNN_Soft_S.glsl",
            "Anime4K_Upscale_CNN_x2_VL.glsl",
            "Anime4K_Upscale_CNN_x2_M.glsl",
            "Anime4K_Upscale_CNN_x2_S.glsl",
            "Anime4K_Upscale_Denoise_CNN_x2_VL.glsl",
            "Anime4K_Upscale_Denoise_CNN_x2_M.glsl"
        ]

        check("Found at least 12 shader files", shaderFiles.filter { $0.hasSuffix(".glsl") }.count >= 12)

        for expected in expectedShaders {
            let path = "\(shadersDir)/\(expected)"
            if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                check("\(expected) is readable and non-empty", !content.isEmpty)
                check("\(expected) contains //!HOOK directive", content.contains("//!HOOK"))
                check("\(expected) contains //!DESC directive", content.contains("//!DESC"))
            } else {
                check("\(expected) exists and is readable", false, "Missing or unreadable")
            }
        }

        print("\nShaderIntegrityTests Results: \(passed) passed, \(failed) failed\n")
        if failed > 0 { exit(1) }
    }
}

