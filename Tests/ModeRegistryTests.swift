// Tests/ModeRegistryTests.swift
// TDD Unit tests for Anime4KMode and ModeCategory registry.
// Asserts that No-Upscale modes (13-15) and ModeCategory.noUpscale are removed,
// and that all 21 remaining modes have valid configurations and upscaling flags.

import Foundation

struct ModeRegistryTests {
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

        // Expected mode IDs: HQ (1-6), Fast (7-12), NeuralSR (16-18), Special (19-24)
        let expectedIDs: [Int] = [
            1, 2, 3, 4, 5, 6,       // HQ
            7, 8, 9, 10, 11, 12,    // Fast
            16, 17, 18,             // NeuralSR
            19, 20, 21, 22, 23, 24  // Special (CoreML + MetalFX)
        ]

        let actualModes = Anime4KMode.allCases
        let actualIDs = actualModes.map(\.rawValue)

        check("Mode count is exactly 21", actualModes.count == 21, "got \(actualModes.count)")
        check("Mode IDs match expected 21 upscale modes", actualIDs == expectedIDs, "got \(actualIDs)")

        // Mode categories
        let categories = ModeCategory.allCases
        let categoryNames = categories.map(\.displayName)
        check("Category count is exactly 4", categories.count == 4, "got \(categories.count)")
        check("No 'noUpscale' category exists", !categoryNames.contains { $0.contains("No Upscale") })

        // Every mode involves upscaling
        for mode in actualModes {
            check("Mode \(mode.rawValue) involves upscaling", mode.involvesUpscaling == true)
        }

        // Every GLSL mode (1-12) has at least one shader marked as isUpscaler
        for mode in actualModes where !mode.isNeuralSR && !mode.isSpecial && !mode.isMetalFX {
            let shaders = mode.shaders
            check("Mode \(mode.rawValue) has non-empty shaders", !shaders.isEmpty)
            check("Mode \(mode.rawValue) contains upscaling shader", shaders.contains { $0.isUpscaler })
        }

        print("\nModeRegistryTests Results: \(passed) passed, \(failed) failed\n")
        if failed > 0 { exit(1) }
    }
}

ModeRegistryTests.main()

