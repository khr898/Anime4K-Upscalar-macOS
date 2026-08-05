// Anime4K-Upscaler/Utilities/TilePlanner.swift
//
// Pure-Foundation tile-plan math factored out of CoreMLUpscaler.upscale so the
// edge-clamp + overlap-halo seam logic is unit-testable without CoreML / AVFoundation
// / CoreImage. No behavior change at the call site: the plan list drives the same
// crop/infer/blit loop. One improvement — duplicate plans (same topX,topY) produced
// by the step iteration clamping to the far edge are deduped, since they crop, infer,
// and blit identical regions idempotently. The deduped set covers the frame exactly
// the same as the raw set; it just stops dispatching the same tile twice.

import Foundation

enum TilePlanner {
    /// One tile placement: where to crop from the source (top-left origin, BGRA),
    /// and which sub-rect of the inferred tile is valid (the interior, excluding
    /// the overlap halo on edges that are NOT the frame boundary).
    struct Plan: Equatable {
        let topX: Int
        let topY: Int
        let cropW: Int
        let cropH: Int
        let validLeft: Int
        let validTop: Int
        let validW: Int
        let validH: Int
    }

    /// Build the tile plan for a `frameW × frameH` frame using a `tileW × tileH`
    /// model input tile with `overlap`-px halo. Plans are deduped by (topX, topY).
    /// Degenerate dims (≤0 frame or tile) return an empty plan list.
    static func plans(frameW: Int, frameH: Int,
                      tileW: Int, tileH: Int,
                      overlap: Int) -> [Plan] {
        guard frameW > 0, frameH > 0, tileW > 0, tileH > 0 else { return [] }
        let stepX = max(1, tileW - 2 * overlap)
        let stepY = max(1, tileH - 2 * overlap)

        var seen: Set<Int> = []          // dedup key = topX * 100_000 + topY (dims are frame pixels)
        var out: [Plan] = []
        var y = 0
        while y < frameH {
            let topY = min(y, max(0, frameH - tileH))
            var x = 0
            while x < frameW {
                let topX = min(x, max(0, frameW - tileW))
                let cropW = min(tileW, frameW - topX)
                let cropH = min(tileH, frameH - topY)
                let validLeft  = (topX == 0) ? 0 : overlap
                let validTop   = (topY == 0) ? 0 : overlap
                let validRight = (topX + tileW >= frameW) ? cropW : cropW - overlap
                let validBot   = (topY + tileH >= frameH) ? cropH : cropH - overlap
                let key = topX * 100_000 + topY
                if !seen.contains(key) {
                    seen.insert(key)
                    out.append(Plan(topX: topX, topY: topY,
                                    cropW: cropW, cropH: cropH,
                                    validLeft: validLeft, validTop: validTop,
                                    validW: max(0, validRight - validLeft),
                                    validH: max(0, validBot - validTop)))
                }
                x += stepX
            }
            y += stepY
        }
        return out
    }
}