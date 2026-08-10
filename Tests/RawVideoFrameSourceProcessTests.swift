// Tests/RawVideoFrameSourceProcessTests.swift
// Standalone assert-based self-check for RawVideoFrameSource's failure
// detection: terminationStatus, framesPulled, hasFailed, and the 0-frame /
// nonzero-exit gating the Special pipeline uses to retry decode with the
// libdav1d software fallback (or surface the real error instead of a
// misleading "Remux exited 183").
//
// Uses /bin/sh as a fake ffmpeg so no real ffmpeg is required for these unit
// checks. Compile + run outside Xcode:
//   swiftc Anime4K-Upscaler/Utilities/FrameAccumulator.swift \
//          Anime4K-Upscaler/Utilities/RawVideoFrameSource.swift \
//          Tests/RawVideoFrameSourceProcessTests.swift -o /tmp/rvproc && /tmp/rvproc

import Foundation
import CoreVideo

@main
struct RawVideoFrameSourceProcessTests {
    static func main() {
        var passed = 0
        var failed = 0

        func check(_ name: String, _ condition: Bool, _ detail: String = "") {
            if condition { print("PASS: \(name)"); passed += 1 }
            else { print("FAIL: \(name) \(detail)"); failed += 1 }
        }

        let env = ProcessInfo.processInfo.environment
        // 2x2 BGRA = 16 bytes per frame.
        let w = 2, h = 2

        // Fake ffmpeg that writes exactly one 16-byte frame to stdout, exits 0.
        func makeSource(_ script: String) -> RawVideoFrameSource {
            RawVideoFrameSource(executableURL: URL(fileURLWithPath: "/bin/sh"),
                                arguments: ["-c", script],
                                width: w, height: h, environment: env)
        }

        do {
            // Test A: one frame, clean exit 0 → not failed, one frame pulled.
            let s = makeSource("head -c 16 /dev/zero")
            try? s.start()
            let f1 = s.nextFrame()
            let f2 = s.nextFrame()
            s.waitUntilExited()
            check("A: one frame produced", f1 != nil, "got nil")
            check("A: EOF after one frame", f2 == nil, "got extra frame")
            check("A: terminationStatus 0", s.terminationStatus == 0, "got \(String(describing: s.terminationStatus))")
            check("A: framesPulled == 1", s.framesPulled == 1, "got \(s.framesPulled)")
            check("A: hasFailed false", !s.hasFailed, "should not flag a clean decode")
        }

        do {
            // Test B: zero frames, exit 1 → failed (the AV1-unsupported case).
            let s = makeSource("echo err >&2; exit 1")
            try? s.start()
            let f1 = s.nextFrame()
            s.waitUntilExited()
            check("B: no frame produced", f1 == nil, "got a frame")
            check("B: terminationStatus 1", s.terminationStatus == 1, "got \(String(describing: s.terminationStatus))")
            check("B: framesPulled == 0", s.framesPulled == 0, "got \(s.framesPulled)")
            check("B: hasFailed true (0 frames + nonzero exit)", s.hasFailed, "must flag decode failure")
        }

        do {
            // Test C: one frame then exit 1 (mid-stream error) → NOT a launch
            // failure: frames were produced, so the retry ladder must not fire.
            let s = makeSource("head -c 16 /dev/zero; exit 1")
            try? s.start()
            let f1 = s.nextFrame()
            let f2 = s.nextFrame()
            s.waitUntilExited()
            check("C: one frame produced", f1 != nil, "got nil")
            check("C: EOF after one frame", f2 == nil, "got extra frame")
            check("C: terminationStatus 1", s.terminationStatus == 1, "got \(String(describing: s.terminationStatus))")
            check("C: framesPulled == 1", s.framesPulled == 1, "got \(s.framesPulled)")
            check("C: hasFailed false (frames produced despite nonzero exit)", !s.hasFailed,
                  "mid-stream error is not a launch failure")
        }

        do {
            // Test D: probe (nextRawFrame) + pushback. The pipeline pulls one raw
            // frame to test whether a decode mode works, then pushes it back so
            // the encode loop's first nextFrame() returns it. The pushed frame
            // must round-trip into a CVPixelBuffer and framesPulled must count
            // it exactly once (not zero, not twice).
            let s = makeSource("head -c 16 /dev/zero")
            try? s.start()
            let raw = s.nextRawFrame()
            check("D: nextRawFrame returns 16 bytes", raw?.count == 16, "got \(raw?.count ?? -1)")
            if let raw { s.pushFrame(raw) }
            let f1 = s.nextFrame()
            let f2 = s.nextFrame()
            s.waitUntilExited()
            check("D: pushed-back frame returns as CVPixelBuffer", f1 != nil, "got nil")
            check("D: EOF after pushed-back frame", f2 == nil, "got extra frame")
            check("D: framesPulled == 1 (probe not double-counted)", s.framesPulled == 1, "got \(s.framesPulled)")
        }

        print("\n\(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}