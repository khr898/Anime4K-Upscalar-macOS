// Anime4K-Upscaler/Utilities/FrameRedundancyCache.swift
// Pure-Foundation duplicate-frame detector for the temporal-redundancy skip
// (plan Phase 9 / N1). Anime = limited animation; 24fps containers often hold
// ≤12fps unique art frames, the rest byte-identical or near-identical dups.
// Reusing the previous upscaled output for a dup (new PTS) skips ANE infer + blit
// — the biggest anime-specific throughput win.
//
// No AVFoundation/CoreVideo/CoreML dependency on purpose: unit-testable standalone
// via `swiftc` (see Tests/FrameRedundancyTests.swift). CVPixelBuffer/PTS gluing lives
// in ProcessingEngine.nextUpscaledFrame, not here.
//
// Signature: 16×9 luma grid (BGRA G channel, byte offset 1, as a luma proxy),
// 144 cells, strided sampling. Dup iff mean cell diff < dupThreshold AND max cell
// diff < sceneChangeMaxCellDiff. The per-cell max cap catches a single large moving
// region that keeps the mean low (slow-pan guard): fresh even when mean < threshold.
// shouldReuse NEVER updates prev — only record() does — so a queried-but-unrecorded
// fresh frame leaves prev intact (caller owns when to record).

import Foundation

public struct FrameRedundancyCache {
    public static let gridW = 16
    public static let gridH = 9
    public static let cellCount = 16 * 9
    private let cellCount: Int

    /// Mean cell diff below this counts as a dup (luma units, 0–255).
    private let dupThreshold: Double
    /// Per-cell diff cap: any single cell above this forces fresh (slow-pan guard).
    private let sceneChangeMaxCellDiff: Double

    private var prevSignature: [UInt8]?
    private var prevW = 0
    private var prevH = 0

    /// - Parameters:
    ///   - dupThreshold: mean luma diff below which a frame reuses the previous (default 4).
    ///   - sceneChangeMaxCellDiff: per-cell cap; a single cell above this forces fresh (default 20).
    public init(dupThreshold: Double = 4.0, sceneChangeMaxCellDiff: Double = 20.0) {
        self.dupThreshold = dupThreshold
        self.sceneChangeMaxCellDiff = sceneChangeMaxCellDiff
        self.cellCount = 16 * 9
    }

    /// True = reuse the previous upscaled output (skip infer); false = infer fresh.
    /// Safe defaults: no prev, empty data, zero dims, or dimension mismatch → fresh
    /// (never falsely reuse). Does NOT mutate `prev`.
    public func shouldReuse(currentFrame: Data, width: Int, height: Int) -> Bool {
        guard let prev = prevSignature,
              width > 0, height > 0,
              width == prevW, height == prevH,
              currentFrame.count >= width * height * 4 else { return false }
        let sig = signature(of: currentFrame, width: width, height: height)
        return compare(sig, against: prev)
    }

    /// Signature-based entry for CVPixelBuffer callers (ProcessingEngine): the
    /// caller builds the 144-byte luma grid from a locked CVPixelBuffer (with
    /// bytesPerRow stride) and passes it here — no full-frame Data copy. Caller
    /// guarantees constant frame size; dims are not re-checked on this path.
    public func shouldReuse(signature: [UInt8]) -> Bool {
        guard let prev = prevSignature, signature.count == cellCount else { return false }
        return compare(signature, against: prev)
    }

    /// Record a fresh frame's signature as the new "previous".
    public mutating func record(currentFrame: Data, width: Int, height: Int) {
        guard width > 0, height > 0,
              currentFrame.count >= width * height * 4 else { return }
        prevSignature = signature(of: currentFrame, width: width, height: height)
        prevW = width
        prevH = height
    }

    /// Signature-based record (CVPixelBuffer path). dims not tracked — a later
    /// Data-path query degrades to fresh (safe), but the two paths are not mixed
    /// in use (ProcessingEngine uses signature-only; tests use Data-only).
    public mutating func record(signature: [UInt8]) {
        guard signature.count == cellCount else { return }
        prevSignature = signature
        prevW = 0
        prevH = 0
    }

    /// Reset per job / per source switch.
    public mutating func reset() {
        prevSignature = nil
        prevW = 0
        prevH = 0
    }

    /// Core compare: mean cell diff < dupThreshold AND max cell diff < cap.
    private func compare(_ sig: [UInt8], against prev: [UInt8]) -> Bool {
        var sum = 0
        var maxCell = 0
        for i in 0..<cellCount {
            let d = abs(Int(sig[i]) - Int(prev[i]))
            sum += d
            if d > maxCell { maxCell = d }
        }
        let mean = Double(sum) / Double(cellCount)
        return mean < dupThreshold && Double(maxCell) < sceneChangeMaxCellDiff
    }

    /// 16×9 strided luma grid from BGRA bytes (G channel at offset 1).
    private func signature(of frame: Data, width: Int, height: Int) -> [UInt8] {
        let strideX = max(1, width / FrameRedundancyCache.gridW)
        let strideY = max(1, height / FrameRedundancyCache.gridH)
        var sig = [UInt8](repeating: 0, count: cellCount)
        for cy in 0..<FrameRedundancyCache.gridH {
            for cx in 0..<FrameRedundancyCache.gridW {
                let px = min(cx * strideX, width - 1)
                let py = min(cy * strideY, height - 1)
                let off = (py * width + px) * 4 + 1   // G = luma proxy
                sig[cy * FrameRedundancyCache.gridW + cx] = frame[off]
            }
        }
        return sig
    }
}