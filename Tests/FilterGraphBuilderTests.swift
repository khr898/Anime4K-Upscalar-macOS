// Tests/FilterGraphBuilderTests.swift
// Exhaustive unit tests for sequential libplacebo filtergraph construction.

import Foundation

// MARK: - Standalone Enum & Model Mock for Sterile Test Execution

enum TestShader: String, CaseIterable {
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
}

enum TestMode: Int, CaseIterable {
    case modeA_HQ = 1
    case modeB_HQ = 2
    case modeC_HQ = 3
    case modeAA_HQ = 4
    case modeBB_HQ = 5
    case modeCA_HQ = 6
    case modeA_Fast = 7
    case modeB_Fast = 8
    case modeC_Fast = 9
    case modeAA_Fast = 10
    case modeBB_Fast = 11
    case modeCA_Fast = 12

    func shaderPipeline(for scale: Int) -> [(shader: TestShader, scales2x: Bool)] {
        switch self {
        case .modeA_HQ:
            var s: [(TestShader, Bool)] = [(.clampHighlights, false), (.restoreCNN_VL, false)]
            if scale >= 2 { s.append((.upscaleCNN_x2_VL, true)) }
            if scale >= 4 { s.append((.upscaleCNN_x2_M, true)) }
            return s

        case .modeB_HQ:
            var s: [(TestShader, Bool)] = [(.clampHighlights, false), (.restoreCNNSoft_VL, false)]
            if scale >= 2 { s.append((.upscaleCNN_x2_VL, true)) }
            if scale >= 4 { s.append((.upscaleCNN_x2_M, true)) }
            return s

        case .modeC_HQ:
            var s: [(TestShader, Bool)] = [(.clampHighlights, false)]
            if scale >= 2 { s.append((.upscaleDenoiseCNN_x2_VL, true)) }
            if scale >= 4 { s.append((.upscaleCNN_x2_M, true)) }
            return s

        case .modeAA_HQ:
            var s: [(TestShader, Bool)] = [(.clampHighlights, false), (.restoreCNN_VL, false)]
            if scale == 2 {
                s.append((.upscaleCNN_x2_VL, true))
                s.append((.restoreCNN_M, false))
            } else if scale >= 4 {
                s.append((.upscaleCNN_x2_VL, true))
                s.append((.restoreCNN_M, false))
                s.append((.upscaleCNN_x2_M, true))
            }
            return s

        case .modeBB_HQ:
            var s: [(TestShader, Bool)] = [(.clampHighlights, false), (.restoreCNNSoft_VL, false)]
            if scale == 2 {
                s.append((.upscaleCNN_x2_VL, true))
                s.append((.restoreCNNSoft_M, false))
            } else if scale >= 4 {
                s.append((.upscaleCNN_x2_VL, true))
                s.append((.restoreCNNSoft_M, false))
                s.append((.upscaleCNN_x2_M, true))
            }
            return s

        case .modeCA_HQ:
            var s: [(TestShader, Bool)] = [(.clampHighlights, false)]
            if scale == 2 {
                s.append((.upscaleDenoiseCNN_x2_VL, true))
                s.append((.restoreCNN_M, false))
            } else if scale >= 4 {
                s.append((.upscaleDenoiseCNN_x2_VL, true))
                s.append((.restoreCNN_M, false))
                s.append((.upscaleCNN_x2_M, true))
            }
            return s

        case .modeA_Fast:
            var s: [(TestShader, Bool)] = [(.clampHighlights, false), (.restoreCNN_M, false)]
            if scale >= 2 { s.append((.upscaleCNN_x2_M, true)) }
            if scale >= 4 { s.append((.upscaleCNN_x2_S, true)) }
            return s

        case .modeB_Fast:
            var s: [(TestShader, Bool)] = [(.clampHighlights, false), (.restoreCNNSoft_M, false)]
            if scale >= 2 { s.append((.upscaleCNN_x2_M, true)) }
            if scale >= 4 { s.append((.upscaleCNN_x2_S, true)) }
            return s

        case .modeC_Fast:
            var s: [(TestShader, Bool)] = [(.clampHighlights, false)]
            if scale >= 2 { s.append((.upscaleDenoiseCNN_x2_M, true)) }
            if scale >= 4 { s.append((.upscaleCNN_x2_S, true)) }
            return s

        case .modeAA_Fast:
            var s: [(TestShader, Bool)] = [(.clampHighlights, false), (.restoreCNN_M, false)]
            if scale == 2 {
                s.append((.upscaleCNN_x2_M, true))
                s.append((.restoreCNN_S, false))
            } else if scale >= 4 {
                s.append((.upscaleCNN_x2_M, true))
                s.append((.restoreCNN_S, false))
                s.append((.upscaleCNN_x2_S, true))
            }
            return s

        case .modeBB_Fast:
            var s: [(TestShader, Bool)] = [(.clampHighlights, false), (.restoreCNNSoft_M, false)]
            if scale == 2 {
                s.append((.upscaleCNN_x2_M, true))
                s.append((.restoreCNNSoft_S, false))
            } else if scale >= 4 {
                s.append((.upscaleCNN_x2_M, true))
                s.append((.restoreCNNSoft_S, false))
                s.append((.upscaleCNN_x2_S, true))
            }
            return s

        case .modeCA_Fast:
            var s: [(TestShader, Bool)] = [(.clampHighlights, false)]
            if scale == 2 {
                s.append((.upscaleDenoiseCNN_x2_M, true))
                s.append((.restoreCNN_S, false))
            } else if scale >= 4 {
                s.append((.upscaleDenoiseCNN_x2_M, true))
                s.append((.restoreCNN_S, false))
                s.append((.upscaleCNN_x2_S, true))
            }
            return s
        }
    }

    func buildFilterGraph(scale: Int, pixelFormat: String, shaderDir: String) -> String {
        let stages = shaderPipeline(for: scale)
        guard !stages.isEmpty else { return "format=\(pixelFormat)" }

        var filterComponents: [String] = ["hwupload"]
        for (shader, scales2x) in stages {
            let path = "\(shaderDir)/\(shader.rawValue)".replacingOccurrences(of: "'", with: "'\\''")
            if scales2x {
                filterComponents.append("libplacebo=w=iw*2:h=ih*2:custom_shader_path='\(path)':format=\(pixelFormat)")
            } else {
                filterComponents.append("libplacebo=custom_shader_path='\(path)':format=\(pixelFormat)")
            }
        }
        filterComponents.append("hwdownload")
        filterComponents.append("format=\(pixelFormat)")
        return filterComponents.joined(separator: ",")
    }
}

@main
struct FilterGraphBuilderTests {
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

        let shaderDir = "/Applications/Anime4K Upscaler.app/Contents/Resources/Shaders"

        // 1. Test Mode A (HQ) @ 2x
        let modeA2x = TestMode.modeA_HQ.buildFilterGraph(scale: 2, pixelFormat: "p010le", shaderDir: shaderDir)
        let stagesA2x = modeA2x.components(separatedBy: "libplacebo")
        check("Mode A (HQ) 2x has 3 libplacebo stages", stagesA2x.count - 1 == 3)
        check("Mode A (HQ) 2x starts with Clamp (1x)", modeA2x.contains("libplacebo=custom_shader_path='\(shaderDir)/Anime4K_Clamp_Highlights.glsl':format=p010le"))
        check("Mode A (HQ) 2x has Restore VL (1x)", modeA2x.contains("libplacebo=custom_shader_path='\(shaderDir)/Anime4K_Restore_CNN_VL.glsl':format=p010le"))
        check("Mode A (HQ) 2x has Upscale VL (2x)", modeA2x.contains("libplacebo=w=iw*2:h=ih*2:custom_shader_path='\(shaderDir)/Anime4K_Upscale_CNN_x2_VL.glsl':format=p010le"))
        check("Mode A (HQ) 2x does NOT include Upscale M", !modeA2x.contains("Anime4K_Upscale_CNN_x2_M.glsl"))

        // 2. Test Mode A (HQ) @ 4x
        let modeA4x = TestMode.modeA_HQ.buildFilterGraph(scale: 4, pixelFormat: "p010le", shaderDir: shaderDir)
        let stagesA4x = modeA4x.components(separatedBy: "libplacebo")
        check("Mode A (HQ) 4x has 4 libplacebo stages", stagesA4x.count - 1 == 4)
        check("Mode A (HQ) 4x includes Upscale VL and Upscale M",
              modeA4x.contains("libplacebo=w=iw*2:h=ih*2:custom_shader_path='\(shaderDir)/Anime4K_Upscale_CNN_x2_VL.glsl':format=p010le") &&
              modeA4x.contains("libplacebo=w=iw*2:h=ih*2:custom_shader_path='\(shaderDir)/Anime4K_Upscale_CNN_x2_M.glsl':format=p010le"))

        // 3. Test Mode A+A (HQ) @ 2x vs 4x
        let modeAA2x = TestMode.modeAA_HQ.buildFilterGraph(scale: 2, pixelFormat: "p010le", shaderDir: shaderDir)
        check("Mode A+A 2x has 4 libplacebo stages (Clamp, Restore VL, Upscale VL 2x, Restore M 1x)", (modeAA2x.components(separatedBy: "libplacebo").count - 1) == 4)
        check("Mode AA HQ 2x contains Upscale 2x BEFORE Restore M",
              modeAA2x.contains("libplacebo=w=iw*2:h=ih*2:custom_shader_path='\(shaderDir)/Anime4K_Upscale_CNN_x2_VL.glsl':format=p010le,libplacebo=custom_shader_path='\(shaderDir)/Anime4K_Restore_CNN_M.glsl':format=p010le"))

        // Test 4: Mode B (HQ) 2x
        let modeB2x = TestMode.modeB_HQ.buildFilterGraph(scale: 2, pixelFormat: "p010le", shaderDir: shaderDir)
        check("Mode B HQ 2x contains Restore_CNN_Soft_VL",
              modeB2x.contains("Anime4K_Restore_CNN_Soft_VL.glsl"))

        // Test 5: Mode C (HQ) 2x
        let modeC2x = TestMode.modeC_HQ.buildFilterGraph(scale: 2, pixelFormat: "p010le", shaderDir: shaderDir)
        check("Mode C HQ 2x contains Upscale_Denoise_CNN_x2_VL",
              modeC2x.contains("Anime4K_Upscale_Denoise_CNN_x2_VL.glsl"))

        // Test 6: SVT-AV1 Pixel format propagation
        let modeA2xAV1 = TestMode.modeA_HQ.buildFilterGraph(scale: 2, pixelFormat: "yuv420p10le", shaderDir: shaderDir)
        check("SVT-AV1 pixel format yuv420p10le propagates to all stages",
              !modeA2xAV1.contains("format=p010le") && modeA2xAV1.contains("format=yuv420p10le"))

        // Test 7: Fast modes (Medium / Small shaders)
        let modeFast2x = TestMode.modeA_Fast.buildFilterGraph(scale: 2, pixelFormat: "p010le", shaderDir: shaderDir)
        check("Mode A Fast 2x uses Restore M and Upscale M",
              modeFast2x.contains("Anime4K_Restore_CNN_M.glsl") &&
              modeFast2x.contains("libplacebo=w=iw*2:h=ih*2:custom_shader_path='\(shaderDir)/Anime4K_Upscale_CNN_x2_M.glsl':format=p010le"))

        let modeFast4x = TestMode.modeA_Fast.buildFilterGraph(scale: 4, pixelFormat: "p010le", shaderDir: shaderDir)
        check("Mode A Fast 4x appends Upscale S 2x",
              modeFast4x.contains("libplacebo=w=iw*2:h=ih*2:custom_shader_path='\(shaderDir)/Anime4K_Upscale_CNN_x2_S.glsl':format=p010le"))

        print("\nFilterGraphBuilderTests Results: \(passed) passed, \(failed) failed\n")
        if failed > 0 { exit(1) }
    }
}
