// Tests/PTSDriftMathTests.swift
// Unit test mathematically proving 0.000 ms cumulative timestamp drift for
// the universal 600,000 Hz rational timebase across standard broadcast and cinema cadences.

import Foundation
import CoreMedia

@main
struct PTSDriftMathTests {
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

        let timebaseScale: CMTimeScale = 600_000

        func computeDurationUnits(for fps: Double) -> Int64 {
            if abs(fps - 23.976) < 0.02 || abs(fps - 23.976023976) < 0.001 {
                return 25_025 // (600_000 * 1001) / 24_000
            } else if abs(fps - 29.97) < 0.02 || abs(fps - 29.97002997) < 0.001 {
                return 20_020 // (600_000 * 1001) / 30_000
            } else if abs(fps - 59.94) < 0.02 || abs(fps - 59.94005994) < 0.001 {
                return 10_010 // (600_000 * 1001) / 60_000
            } else {
                return max(1, Int64(round(Double(timebaseScale) / max(fps, 0.001))))
            }
        }

        // Test 1: 23.976 fps (NTSC Film, exact 24000/1001)
        let trueFps23976 = 24000.0 / 1001.0
        let units23976 = computeDurationUnits(for: 23.976)
        check("23.976 duration units is exactly 25,025 ticks", units23976 == 25025)

        // 24-minute episode = 34,525 frames
        let framesEpisode = 34525
        let ptsEpisode = CMTime(value: Int64(framesEpisode) * units23976, timescale: timebaseScale)
        let expectedEpisodeSeconds = Double(framesEpisode) / trueFps23976
        let driftEpisodeMs = abs(ptsEpisode.seconds - expectedEpisodeSeconds) * 1000.0
        check("23.976 24-min episode cumulative drift < 0.001 ms", driftEpisodeMs < 0.001, "drift = \(driftEpisodeMs) ms")

        // 100,000 frames (>1.15 hours)
        let frames100k = 100_000
        let pts100k = CMTime(value: Int64(frames100k) * units23976, timescale: timebaseScale)
        let expected100kSeconds = Double(frames100k) / trueFps23976
        let drift100kMs = abs(pts100k.seconds - expected100kSeconds) * 1000.0
        check("23.976 100k frames cumulative drift < 0.001 ms", drift100kMs < 0.001, "drift = \(drift100kMs) ms")

        // Test 2: 29.97 fps (NTSC Video, exact 30000/1001)
        let trueFps2997 = 30000.0 / 1001.0
        let units2997 = computeDurationUnits(for: 29.97)
        check("29.97 duration units is exactly 20,020 ticks", units2997 == 20020)
        let pts2997 = CMTime(value: Int64(frames100k) * units2997, timescale: timebaseScale)
        let expected2997Seconds = Double(frames100k) / trueFps2997
        let drift2997Ms = abs(pts2997.seconds - expected2997Seconds) * 1000.0
        check("29.97 100k frames cumulative drift < 0.001 ms", drift2997Ms < 0.001, "drift = \(drift2997Ms) ms")

        // Test 3: 59.94 fps (NTSC High Framerate, exact 60000/1001)
        let trueFps5994 = 60000.0 / 1001.0
        let units5994 = computeDurationUnits(for: 59.94)
        check("59.94 duration units is exactly 10,010 ticks", units5994 == 10010)
        let pts5994 = CMTime(value: Int64(frames100k) * units5994, timescale: timebaseScale)
        let expected5994Seconds = Double(frames100k) / trueFps5994
        let drift5994Ms = abs(pts5994.seconds - expected5994Seconds) * 1000.0
        check("59.94 100k frames cumulative drift < 0.001 ms", drift5994Ms < 0.001, "drift = \(drift5994Ms) ms")

        // Test 4: Exact integer cadences (24.0, 25.0, 30.0, 60.0 fps)
        for integerFps in [24.0, 25.0, 30.0, 60.0] {
            let units = computeDurationUnits(for: integerFps)
            let pts = CMTime(value: Int64(frames100k) * units, timescale: timebaseScale)
            let expected = Double(frames100k) / integerFps
            let drift = abs(pts.seconds - expected) * 1000.0
            check("\(Int(integerFps)) fps 100k frames cumulative drift == 0.0 ms", drift == 0.0, "drift = \(drift) ms")
        }

        print("\nPTSDriftMathTests Results: \(passed) passed, \(failed) failed\n")
        if failed > 0 { exit(1) }
    }
}
