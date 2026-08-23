// Tests/FrameRedundancyTests.swift
// Standalone assert-based self-check for FrameRedundancyCache.
// Compile + run outside Xcode (pure Foundation, no AVFoundation/CoreML dep):
//   swiftc Anime4K-Upscaler/Utilities/FrameRedundancyCache.swift \
//          Tests/FrameRedundancyTests.swift -o /tmp/reduntest && /tmp/reduntest
// Mirrors Tests/FrameAccumulatorTests.swift: @main + print PASS/FAIL + exit(1) on fail.
//
// What this proves:
//   - first frame is always fresh (no prev) → no reuse
//   - identical / near-identical frame → reuse (skip infer)
//   - scene change → fresh
//   - record() updates the "previous" so subsequent dups compare against the new scene
//   - reset() forces the next frame fresh (per-job / per-source-switch hygiene)
//   - safe defaults: empty data, zero dims, dimension mismatch → fresh (never falsely reuse)
//   - slow-pan guard: a single large moving region forces fresh even when the mean
//     cell diff is below the dup threshold (per-cell max cap, not just mean)

import Foundation

@main
struct FrameRedundancyTests {
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

        // --- Test frame helpers (BGRA, 4 bytes/pixel, G channel at offset 1 = luma proxy). ---
        // Grid is 16x9. Use w=16,h=9 so each cell is exactly one pixel → per-cell control exact.
        let w = 16, h = 9
        let bytesPerPixel = 4
        let frameBytes = w * h * bytesPerPixel

        func solidFrame(_ g: UInt8) -> Data {
            var d = Data(count: frameBytes)
            for i in 0..<(w * h) {
                d[i * 4 + 0] = 0          // B
                d[i * 4 + 1] = g          // G (luma)
                d[i * 4 + 2] = 0          // R
                d[i * 4 + 3] = 255        // A
            }
            return d
        }

        // Frame where every cell has luma = base except the cell at (cx, cy) = value.
        func frameWithOneCell(base: UInt8, cellX: Int, cellY: Int, value: UInt8) -> Data {
            var d = solidFrame(base)
            // For w=16,h=9, cell (cx,cy) samples pixel (cx, cy) directly.
            let px = cellX, py = cellY
            d[(py * w + px) * 4 + 1] = value
            return d
        }

        // Frame where every cell differs from `base` by exactly `delta` (uniform noise).
        func frameUniformDelta(base: UInt8, delta: UInt8) -> Data {
            let v = base &+ delta
            return solidFrame(v)
        }

        // --- Case 1: first frame is always fresh (no previous). ---
        do {
            var cache = FrameRedundancyCache()
            let reuse = cache.shouldReuse(currentFrame: solidFrame(100), width: w, height: h)
            check("first frame fresh", reuse == false, "got reuse=\(reuse)")
        }

        // --- Case 2: identical second frame → reuse. ---
        do {
            var cache = FrameRedundancyCache()
            let f = solidFrame(100)
            cache.record(currentFrame: f, width: w, height: h)
            let reuse = cache.shouldReuse(currentFrame: f, width: w, height: h)
            check("identical frame reuse", reuse == true, "got reuse=\(reuse)")
        }

        // --- Case 3: near-identical (uniform delta below threshold) → reuse. ---
        do {
            var cache = FrameRedundancyCache()
            cache.record(currentFrame: solidFrame(100), width: w, height: h)
            // delta = 3 luma units across all cells → mean=3, max=3, both under default caps.
            let reuse = cache.shouldReuse(currentFrame: frameUniformDelta(base: 100, delta: 3),
                                          width: w, height: h)
            check("near-identical reuse", reuse == true, "got reuse=\(reuse)")
        }

        // --- Case 4: scene change (large uniform delta) → fresh. ---
        do {
            var cache = FrameRedundancyCache()
            cache.record(currentFrame: solidFrame(100), width: w, height: h)
            let reuse = cache.shouldReuse(currentFrame: solidFrame(200), width: w, height: h)
            check("scene change fresh", reuse == false, "got reuse=\(reuse)")
        }

        // --- Case 5: record() updates prev — after a fresh scene, a dup of the NEW scene reuses. ---
        do {
            var cache = FrameRedundancyCache()
            cache.record(currentFrame: solidFrame(100), width: w, height: h)
            // Scene change to 200.
            let scene2 = solidFrame(200)
            let reuseAtCut = cache.shouldReuse(currentFrame: scene2, width: w, height: h)
            check("scene change to new value fresh", reuseAtCut == false, "got reuse=\(reuseAtCut)")
            cache.record(currentFrame: scene2, width: w, height: h)
            // Now a dup of scene2 must reuse against the NEW prev.
            let reuseDup = cache.shouldReuse(currentFrame: scene2, width: w, height: h)
            check("dup of new scene reuses after record", reuseDup == true, "got reuse=\(reuseDup)")
        }

        // --- Case 6: reset() forces next frame fresh. ---
        do {
            var cache = FrameRedundancyCache()
            let f = solidFrame(100)
            cache.record(currentFrame: f, width: w, height: h)
            check("before reset dup reuses", cache.shouldReuse(currentFrame: f, width: w, height: h) == true)
            cache.reset()
            check("after reset fresh", cache.shouldReuse(currentFrame: f, width: w, height: h) == false)
        }

        // --- Case 7: safe defaults — empty data / zero dims → fresh, never reuse. ---
        do {
            var cache = FrameRedundancyCache()
            cache.record(currentFrame: solidFrame(100), width: w, height: h)
            check("empty data fresh", cache.shouldReuse(currentFrame: Data(), width: w, height: h) == false)
            check("zero width fresh", cache.shouldReuse(currentFrame: solidFrame(100), width: 0, height: h) == false)
            check("zero height fresh", cache.shouldReuse(currentFrame: solidFrame(100), width: w, height: 0) == false)
        }

        // --- Case 8: dimension mismatch (prev 16x9, current 32x18) → fresh (safe; no cross-size compare). ---
        do {
            var cache = FrameRedundancyCache()
            cache.record(currentFrame: solidFrame(100), width: 16, height: 9)
            let reuse = cache.shouldReuse(currentFrame: solidFrame(100), width: 32, height: 18)
            check("dimension mismatch fresh", reuse == false, "got reuse=\(reuse)")
        }

        // --- Case 9: slow-pan guard — one cell with a large change, mean stays low → fresh (max-cell cap). ---
        do {
            var cache = FrameRedundancyCache()
            cache.record(currentFrame: solidFrame(100), width: w, height: h)
            // 143 cells identical, 1 cell jumps by 100. mean = 100/144 ≈ 0.69 (below dup
            // threshold), max = 100 (above the per-cell cap) → must be fresh, not a dup.
            let panFrame = frameWithOneCell(base: 100, cellX: 8, cellY: 4, value: 200)
            let reuse = cache.shouldReuse(currentFrame: panFrame, width: w, height: h)
            check("slow-pan single-region change fresh", reuse == false, "got reuse=\(reuse)")
        }

        // --- Case 10: threshold boundary — uniform delta exactly at default threshold → fresh (strict <). ---
        do {
            var cache = FrameRedundancyCache()
            cache.record(currentFrame: solidFrame(100), width: w, height: h)
            // Default dup threshold is 4.0; uniform delta 4 → mean = 4, 4 < 4 is false → fresh.
            let reuse = cache.shouldReuse(currentFrame: frameUniformDelta(base: 100, delta: 4),
                                          width: w, height: h)
            check("threshold boundary fresh (strict less-than)", reuse == false, "got reuse=\(reuse)")
        }

        // --- Case 11: a fresh (non-dup) frame does NOT update prev — the next dup still compares to the last recorded. ---
        do {
            var cache = FrameRedundancyCache()
            cache.record(currentFrame: solidFrame(100), width: w, height: h)
            // Scene-change frame we do NOT record (simulating: caller asked, got fresh, but
            // record is the caller's responsibility; here we skip it). Next dup of 100 must
            // still reuse because prev is still 100.
            _ = cache.shouldReuse(currentFrame: solidFrame(200), width: w, height: h)
            let reuse = cache.shouldReuse(currentFrame: solidFrame(100), width: w, height: h)
            check("unrecorded fresh does not update prev", reuse == true, "got reuse=\(reuse)")
        }

        // --- Case 12: realistic 1080p frame — signature must not crash on real size and must be deterministic. ---
        do {
            let rw = 1920, rh = 1080
            let rBytes = rw * rh * bytesPerPixel
            var a = Data(count: rBytes)
            for i in 0..<(rw * rh) { a[i * 4 + 1] = UInt8((i * 7) & 0xFF); a[i * 4 + 3] = 255 }
            var cache = FrameRedundancyCache()
            cache.record(currentFrame: a, width: rw, height: rh)
            check("1080p: identical reuse", cache.shouldReuse(currentFrame: a, width: rw, height: rh) == true)
            // Slightly modified copy → deterministic decision (fresh, since many cells change).
            var b = a
            for i in 0..<(rw * rh) { b[i * 4 + 1] = UInt8(((i * 7) &+ 80) & 0xFF) }
            check("1080p: heavily modified fresh", cache.shouldReuse(currentFrame: b, width: rw, height: rh) == false)
        }

        // --- Case 13: custom threshold ctor — a looser threshold reuses what the default rejects. ---
        do {
            var cache = FrameRedundancyCache(dupThreshold: 50, sceneChangeMaxCellDiff: 200)
            cache.record(currentFrame: solidFrame(100), width: w, height: h)
            // delta 30 across all cells: default would fresh (30 > 4), loose reuses (30 < 50, 30 < 200).
            let reuse = cache.shouldReuse(currentFrame: frameUniformDelta(base: 100, delta: 30),
                                          width: w, height: h)
            check("loose threshold reuses bigger delta", reuse == true, "got reuse=\(reuse)")
        }

        print("\n\(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}