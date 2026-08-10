// Tests/FrameAccumulatorTests.swift
// Standalone assert-based self-check for FrameAccumulator.
// Compile + run outside Xcode:
//   swiftc Anime4K-Upscaler/Utilities/FrameAccumulator.swift \
//          Tests/FrameAccumulatorTests.swift -o /tmp/facctest && /tmp/facctest
// No Swift Testing / SPM dependency — pure Foundation, runnable anywhere swiftc is.

import Foundation

@main
struct FrameAccumulatorTests {
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

        // Case 1: one chunk exactly one frame.
        do {
            var acc = FrameAccumulator()
            acc.push(Data(repeating: 0xAA, count: 12))
            let frames = acc.pullFrames(frameSize: 12)
            check("exact-frame chunk", frames.count == 1, "got \(frames.count)")
            check("exact-frame chunk empty remainder", acc.remaining.isEmpty, "got \(acc.remaining.count)")
        }

        // Case 2: frame split across two chunks.
        do {
            var acc = FrameAccumulator()
            acc.push(Data(repeating: 0x01, count: 5))
            let f0 = acc.pullFrames(frameSize: 12)
            check("split: no frame before 2nd chunk", f0.isEmpty, "got \(f0.count)")
            acc.push(Data(repeating: 0x02, count: 7))
            let f1 = acc.pullFrames(frameSize: 12)
            check("split: one frame after 2nd chunk", f1.count == 1, "got \(f1.count)")
            check("split: remainder empty", acc.remaining.isEmpty, "got \(acc.remaining.count)")
        }

        // Case 3: multiple frames in one chunk.
        do {
            var acc = FrameAccumulator()
            acc.push(Data(repeating: 0x03, count: 24))
            let frames = acc.pullFrames(frameSize: 12)
            check("multi-frame one chunk", frames.count == 2, "got \(frames.count)")
            check("multi-frame remainder empty", acc.remaining.isEmpty, "got \(acc.remaining.count)")
        }

        // Case 4: partial trailing bytes at EOF (incomplete last frame).
        do {
            var acc = FrameAccumulator()
            acc.push(Data(repeating: 0x04, count: 15))
            let frames = acc.pullFrames(frameSize: 12)
            check("partial trailing: one complete frame", frames.count == 1, "got \(frames.count)")
            check("partial trailing: 3 bytes remainder", acc.remaining.count == 3, "got \(acc.remaining.count)")
        }

        // Case 5: empty input.
        do {
            var acc = FrameAccumulator()
            acc.push(Data())
            let frames = acc.pullFrames(frameSize: 12)
            check("empty: no frames", frames.isEmpty, "got \(frames.count)")
            check("empty: no remainder", acc.remaining.isEmpty, "got \(acc.remaining.count)")
        }

        // Case 6: nothing pushed at all.
        do {
            var acc = FrameAccumulator()
            let frames = acc.pullFrames(frameSize: 12)
            check("virgin: no frames", frames.isEmpty, "got \(frames.count)")
        }

        // Case 7: byte integrity — exact bytes preserved end-to-end across a split.
        do {
            var acc = FrameAccumulator()
            let frame = Data((0..<12).map { UInt8($0) })   // 0,1,2,...,11
            acc.push(frame[0..<5])
            acc.push(frame[5..<12])
            let frames = acc.pullFrames(frameSize: 12)
            check("byte integrity: one frame", frames.count == 1, "got \(frames.count)")
            check("byte integrity: bytes match", frames.first == frame, "mismatch")
        }

        // Case 8: large frame realistic size (1920*1080*4 = 8294400) fed in random small chunks.
        do {
            let frameSize = 1920 * 1080 * 4
            var acc = FrameAccumulator()
            let blob = Data((0..<frameSize).map { UInt8($0 & 0xFF) })
            // feed in 100KB chunks
            var offset = 0
            while offset < blob.count {
                let end = min(offset + 100_000, blob.count)
                acc.push(blob.subdata(in: offset..<end))
                offset = end
            }
            let frames = acc.pullFrames(frameSize: frameSize)
            check("realistic: one 1080p bgra frame", frames.count == 1, "got \(frames.count)")
            check("realistic: bytes match", frames.first == blob, "mismatch")
            check("realistic: no remainder", acc.remaining.isEmpty, "got \(acc.remaining.count)")
        }

        // Case 9: pullFrame — single frame at a time, leftover stays buffered.
        do {
            var acc = FrameAccumulator()
            acc.push(Data(repeating: 0x05, count: 12))
            let f1 = acc.pullFrame(frameSize: 12)
            let f2 = acc.pullFrame(frameSize: 12)
            check("pullFrame: returns one frame", f1?.count == 12, "got \(f1?.count ?? -1)")
            check("pullFrame: second returns nil", f2 == nil, "got non-nil")
            check("pullFrame: remainder empty", acc.remaining.isEmpty, "got \(acc.remaining.count)")
        }

        // Case 10: pullFrame across split chunks, then a second frame.
        do {
            var acc = FrameAccumulator()
            acc.push(Data(repeating: 0x06, count: 5))
            check("pullFrame: nil before complete", acc.pullFrame(frameSize: 12) == nil, "got frame")
            acc.push(Data(repeating: 0x07, count: 19))   // total 24 -> 2 frames
            let f1 = acc.pullFrame(frameSize: 12)
            let f2 = acc.pullFrame(frameSize: 12)
            check("pullFrame: first after 2nd chunk", f1 != nil, "missing")
            check("pullFrame: second after 2nd chunk", f2 != nil, "missing")
            check("pullFrame: no remainder after 2", acc.remaining.isEmpty, "got \(acc.remaining.count)")
        }

        // Case 11: pullFrame with no data at all.
        do {
            var acc = FrameAccumulator()
            check("pullFrame: nil on virgin", acc.pullFrame(frameSize: 12) == nil, "got frame")
        }

        // Case 12 (regression): pull a frame, then push more — `push` compacts via
        // `removeFirst(readOffset)`, which advances `buffer.startIndex` past the
        // consumed prefix. The next `pullFrame` must slice from `buffer.startIndex`,
        // NOT from 0. Pre-fix this trapped inside `Data.subdata(in:)` (index 0 <
        // startIndex is invalid even when count >= frameSize) — the real-video
        // crash on frame 2+ (EXC_BREAKPOINT in subdata on a4k.rawframesource.state).
        do {
            let frameSize = 1920 * 1080 * 4
            var acc = FrameAccumulator()
            let frameA = Data(repeating: 0xA1, count: frameSize)
            let frameB = Data(repeating: 0xB2, count: frameSize)
            // Feed frameA in small chunks, pull it (readOffset -> frameSize).
            var off = 0
            while off < frameA.count {
                let end = min(off + 100_000, frameA.count)
                acc.push(frameA.subdata(in: off..<end))
                off = end
            }
            let pulledA = acc.pullFrame(frameSize: frameSize)
            check("regression: frame A pulled", pulledA == frameA, "mismatch")
            // Now push frameB — triggers removeFirst(frameSize) inside push,
            // shifting buffer.startIndex to frameSize. Pre-fix: next pull traps.
            acc.push(frameB)
            let pulledB = acc.pullFrame(frameSize: frameSize)
            check("regression: frame B pulled after startIndex shift", pulledB == frameB, "mismatch / would have trapped pre-fix")
            check("regression: no remainder", acc.remaining.isEmpty, "got \(acc.remaining.count)")
        }

        // Case 13 (regression): many frames in a stream with interleaved push/pull
        // — exercises repeated removeFirst startIndex shifts + appends.
        do {
            let frameSize = 1920 * 1080 * 4
            var acc = FrameAccumulator()
            let frames = (0..<8).map { i in Data(repeating: UInt8(i), count: frameSize) }
            for (i, frame) in frames.enumerated() {
                acc.push(frame)
                let pulled = acc.pullFrame(frameSize: frameSize)
                check("regression: stream frame \(i)", pulled == frame, "byte mismatch")
            }
            check("regression: stream no remainder", acc.remaining.isEmpty, "got \(acc.remaining.count)")
        }

        print("\n\(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}