// Tests/TilePlannerTests.swift
// Standalone assert-based self-check for TilePlanner (the edge-clamp tile
// plan math factored out of CoreMLUpscaler.upscale). Pure Foundation — no
// CoreML/AVFoundation/CoreImage — so it compiles + runs outside Xcode:
//   swiftc Anime4K-Upscaler/Utilities/TilePlanner.swift \
//          Tests/TilePlannerTests.swift -o /tmp/tileplan && /tmp/tileplan
// Mirrors Tests/FrameAccumulatorTests.swift: @main + print PASS/FAIL + exit(1).
//
// What this proves:
//   - frame == tile → single plan covering the whole frame (full valid region)
//   - frame < tile  → single plan clamped to frame size (no negative crop)
//   - frame > tile  → grid of plans with overlap halo; interior valid region
//     = tile - 2*overlap; edge plans keep the full edge (no halo on the
//     frame boundary) so the union of valid regions tiles the frame exactly
//   - edge clamping: the last tile top is clamped so the tile stays in-frame
//     (this intentionally produces overlapping/duplicate plans at the edge —
//     the blit overwrites idempotently; matches the pre-refactor loop)
//   - overlap = 0 → valid region == tile, step == tile, exact non-overlapping grid
//   - degenerate inputs (zero/negative dims, zero frame) → empty plan list,
//     never a crash or negative-width plan

import Foundation

@main
struct TilePlannerTests {
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

        // --- Case 1: frame exactly == tile → 1 plan, full valid region. ---
        do {
            let plans = TilePlanner.plans(frameW: 10, frameH: 10, tileW: 10, tileH: 10, overlap: 2)
            check("frame==tile count", plans.count == 1, "got \(plans.count)")
            let p = plans[0]
            check("frame==tile origin", p.topX == 0 && p.topY == 0, "got (\(p.topX),\(p.topY))")
            check("frame==tile crop", p.cropW == 10 && p.cropH == 10, "got (\(p.cropW),\(p.cropH))")
            check("frame==tile valid origin", p.validLeft == 0 && p.validTop == 0)
            check("frame==tile valid size", p.validW == 10 && p.validH == 10,
                  "got (\(p.validW),\(p.validH))")
        }

        // --- Case 2: frame smaller than tile → 1 plan clamped to frame. ---
        do {
            let plans = TilePlanner.plans(frameW: 8, frameH: 6, tileW: 10, tileH: 10, overlap: 2)
            check("frame<tile count", plans.count == 1, "got \(plans.count)")
            let p = plans[0]
            check("frame<tile crop clamped", p.cropW == 8 && p.cropH == 6,
                  "got (\(p.cropW),\(p.cropH))")
            // topX+tw(10) >= width(8) → validRight = cropW = 8; validLeft=0 → validW=8.
            check("frame<tile valid size", p.validW == 8 && p.validH == 6,
                  "got (\(p.validW),\(p.validH))")
        }

        // --- Case 3: 16x16 frame, 10x10 tile, overlap 2 → 4 unique plans
        // (the raw step iteration produces clamped duplicates at the far edge:
        // x,y ∈ {0,6,12} → top {0,6,6}; TilePlanner dedups by (topX,topY) since
        // duplicate plans crop/infer/blit identical regions idempotently).
        // Every valid region is 8x8. ---
        do {
            let plans = TilePlanner.plans(frameW: 16, frameH: 16, tileW: 10, tileH: 10, overlap: 2)
            check("16x16 count", plans.count == 4, "got \(plans.count)")
            let allValid8 = plans.allSatisfy { $0.validW == 8 && $0.validH == 8 }
            check("16x16 all valid 8x8", allValid8)
            // Unique origins (topX,topY) ∈ {(0,0),(6,0),(0,6),(6,6)}.
            let origins = Set(plans.map { "\($0.topX),\($0.topY)" })
            check("16x16 unique origins", origins == ["0,0", "6,0", "0,6", "6,6"],
                  "got \(origins.sorted())")
            let p00 = plans.first { $0.topX == 0 && $0.topY == 0 }
            check("16x16 (0,0) exists", p00 != nil)
            check("16x16 (0,0) valid origin", p00?.validLeft == 0 && p00?.validTop == 0)
            // topX=0 (left edge) → validLeft=0; topX+tw=10 >= 16? no → validRight=8 → validW=8.
            check("16x16 (0,0) validW halo", p00?.validW == 8)
            let p66 = plans.first { $0.topX == 6 && $0.topY == 6 }
            check("16x16 (6,6) exists", p66 != nil)
            // topX=6 (interior) → validLeft=2; topX+tw=16>=16 → validRight=cropW=10 → validW=8.
            check("16x16 (6,6) halo left", p66?.validLeft == 2)
            check("16x16 (6,6) validW", p66?.validW == 8)
        }

        // --- Case 4: the union of valid destinations covers the frame exactly
        // (no gap, no negative). For 16x16/tile10/overlap2, valid destinations
        // (topX+validLeft, topY+validTop) with 8x8 size should cover [0,16)². ---
        do {
            let plans = TilePlanner.plans(frameW: 16, frameH: 16, tileW: 10, tileH: 10, overlap: 2)
            // Collect unique valid-dest origins (in tile coords, pre-nativeScale).
            var covered = Set<String>()
            for p in plans where p.validW > 0 && p.validH > 0 {
                let ox = p.topX + p.validLeft
                let oy = p.topY + p.validTop
                covered.insert("\(ox),\(oy)")
            }
            // Expected unique origins from {0,6,6}×{0,6,6} + halo: (0,0),(8,0),(0,8),(8,8).
            // (topX=0→ox=0; topX=6→ox=6+2=8.) 4 unique 8x8 blocks tile 16x16.
            check("16x16 coverage unique origins",
                  covered == ["0,0", "8,0", "0,8", "8,8"],
                  "got \(covered.sorted())")
        }

        // --- Case 5: overlap 0 → exact non-overlapping grid, valid == tile. ---
        do {
            let plans = TilePlanner.plans(frameW: 20, frameH: 20, tileW: 10, tileH: 10, overlap: 0)
            check("overlap0 count", plans.count == 4, "got \(plans.count)")
            let allFull = plans.allSatisfy { p in
                p.validW == 10 && p.validH == 10 && p.validLeft == 0 && p.validTop == 0
            }
            check("overlap0 valid==tile", allFull)
            // Origins should be exactly the 4 corners (0,0),(10,0),(0,10),(10,10).
            let origins = Set(plans.map { "\($0.topX),\($0.topY)" })
            check("overlap0 origins", origins == ["0,0", "10,0", "0,10", "10,10"],
                  "got \(origins.sorted())")
        }

        // --- Case 6: non-square frame + tile (16 wide x 10 tall, tile 10x6, overlap 2). ---
        // stepX = 6, stepY = 2. x∈{0,6,12}→topX{0,6,6}; y∈{0,2,4,6,8}→topY=min(v,max(0,10-6=4))={0,2,4,4,4}.
        // Just assert no plan has negative validW/validH and all stay in-frame.
        do {
            let plans = TilePlanner.plans(frameW: 16, frameH: 10, tileW: 10, tileH: 6, overlap: 2)
            check("non-square count > 0", plans.count > 0, "got \(plans.count)")
            let noNegatives = plans.allSatisfy { p in
                p.validW >= 0 && p.validH >= 0 && p.cropW > 0 && p.cropH > 0
            }
            check("non-square no negative regions", noNegatives)
            // Every valid dest + size stays within the frame.
            let inFrame = plans.allSatisfy { p -> Bool in
                let ox = p.topX + p.validLeft, oy = p.topY + p.validTop
                return ox >= 0 && oy >= 0 && ox + p.validW <= 16 && oy + p.validH <= 10
            }
            check("non-square all in-frame", inFrame)
        }

        // --- Case 7: degenerate inputs → empty, no crash. ---
        do {
            check("zero frame empty", TilePlanner.plans(frameW: 0, frameH: 0, tileW: 10, tileH: 10, overlap: 2).isEmpty)
            check("zero tile empty", TilePlanner.plans(frameW: 10, frameH: 10, tileW: 0, tileH: 0, overlap: 2).isEmpty)
            check("neg dims empty", TilePlanner.plans(frameW: -5, frameH: 5, tileW: 10, tileH: 10, overlap: 2).isEmpty)
            let big = TilePlanner.plans(frameW: 12, frameH: 12, tileW: 10, tileH: 10, overlap: 10)
            check("overlap>=tile terminates", big.allSatisfy { $0.validW >= 0 && $0.validH >= 0 })
        }

        // --- Case 8: 1080p with 512x512 tiles (step 480 with overlap 16). ---
        do {
            let plans = TilePlanner.plans(frameW: 1920, frameH: 1080, tileW: 512, tileH: 512, overlap: 16)
            check("1080p 512x512 tile count == 12", plans.count == 12, "got \(plans.count)")
            let allInFrame = plans.allSatisfy { p in
                let ox = p.topX + p.validLeft, oy = p.topY + p.validTop
                return ox >= 0 && oy >= 0 && (ox + p.validW) <= 1920 && (oy + p.validH) <= 1080
            }
            check("1080p 512x512 all tiles in frame", allInFrame)
        }

        // --- Case 9: 1080p full-frame bypass (1920x1080 tile). ---
        do {
            let plans = TilePlanner.plans(frameW: 1920, frameH: 1080, tileW: 1920, tileH: 1080, overlap: 16)
            check("full-frame count == 1", plans.count == 1)
            let p = plans[0]
            check("full-frame valid == 1920x1080", p.validW == 1920 && p.validH == 1080 && p.validLeft == 0 && p.validTop == 0)
        }

        // --- Case 10: 4K (3840x2160) with 512x512 tiles. ---
        do {
            let plans = TilePlanner.plans(frameW: 3840, frameH: 2160, tileW: 512, tileH: 512, overlap: 16)
            check("4K 512x512 tile count == 40", plans.count == 40, "got \(plans.count)")
        }

        print("\n\(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}