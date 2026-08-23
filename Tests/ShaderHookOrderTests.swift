// Tests/ShaderHookOrderTests.swift
// Unit test to verify shader hook declarations and ensure Anime4K_Clamp_Highlights.glsl
// uses //!HOOK MAIN exclusively to prevent libplacebo out-of-order execution artifacts.

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

        print("\n\(passed) passed, \(failed) failed\n")
        if failed > 0 { exit(1) }
    }
}
