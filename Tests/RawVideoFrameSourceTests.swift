// Tests/RawVideoFrameSourceTests.swift
// Standalone assert-based self-check for RawVideoFrameSource.makeBGRA.
// Compile + run outside Xcode:
//   swiftc Anime4K-Upscaler/Utilities/FrameAccumulator.swift \
//          Anime4K-Upscaler/Utilities/RawVideoFrameSource.swift \
//          Tests/RawVideoFrameSourceTests.swift -o /tmp/rvtest && /tmp/rvtest
//
// Only the pure CVPixelBuffer factory is unit-tested here. The Process/pipe
// streaming path is integration-verified by the app build + a real encode run.

import Foundation
import CoreVideo

@main
struct RawVideoFrameSourceTests {
    static func main() {
        var passed = 0
        var failed = 0

        func check(_ name: String, _ condition: Bool, _ detail: String = "") {
            if condition { print("PASS: \(name)"); passed += 1 }
            else { print("FAIL: \(name) \(detail)"); failed += 1 }
        }

        // Helper: build source BGRA bytes with a unique pixel pattern.
        func sourceData(width: Int, height: Int) -> Data {
            var d = Data(count: width * height * 4)
            for y in 0..<height {
                for x in 0..<width {
                    let i = (y * width + x) * 4
                    d[i]     = UInt8((x * 17) & 0xFF)      // B
                    d[i + 1] = UInt8((y * 23) & 0xFF)      // G
                    d[i + 2] = UInt8((x ^ y) & 0xFF)       // R
                    d[i + 3] = UInt8(0xFF)                 // A
                }
            }
            return d
        }

        // Helper: read a pixel back from a CVPixelBuffer at (x,y).
        func pixel(_ pb: CVPixelBuffer, x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
            CVPixelBufferLockBaseAddress(pb, [])
            let base = CVPixelBufferGetBaseAddress(pb)!
            let bpr = CVPixelBufferGetBytesPerRow(pb)
            let p = base.advanced(by: y * bpr + x * 4)
            let b = p.load(as: UInt8.self)
            let g = p.advanced(by: 1).load(as: UInt8.self)
            let r = p.advanced(by: 2).load(as: UInt8.self)
            let a = p.advanced(by: 3).load(as: UInt8.self)
            CVPixelBufferUnlockBaseAddress(pb, [])
            return (b, g, r, a)
        }

        // Case 1: 4x3 image, full round-trip pixel integrity.
        do {
            let w = 4, h = 3
            let src = sourceData(width: w, height: h)
            guard let pb = RawVideoFrameSource.makeBGRA(from: src, width: w, height: h) else {
                check("4x3: buffer created", false, "nil"); print("\n\(passed) passed, \(failed) failed"); if failed>0 {exit(1)}; return
            }
            check("4x3: width", CVPixelBufferGetWidth(pb) == w, "got \(CVPixelBufferGetWidth(pb))")
            check("4x3: height", CVPixelBufferGetHeight(pb) == h, "got \(CVPixelBufferGetHeight(pb))")
            check("4x3: format 32BGRA",
                  CVPixelBufferGetPixelFormatType(pb) == kCVPixelFormatType_32BGRA,
                  "got \(CVPixelBufferGetPixelFormatType(pb))")
            var allMatch = true
            for y in 0..<h {
                for x in 0..<w {
                    let (b, g, r, a) = pixel(pb, x: x, y: y)
                    let i = (y * w + x) * 4
                    if b != src[i] || g != src[i+1] || r != src[i+2] || a != src[i+3] {
                        allMatch = false
                    }
                }
            }
            check("4x3: all pixels match", allMatch)
        }

        // Case 2: odd width (5x2) that may trigger bytesPerRow padding — must
        // still round-trip every pixel regardless of padding.
        do {
            let w = 5, h = 2
            let src = sourceData(width: w, height: h)
            guard let pb = RawVideoFrameSource.makeBGRA(from: src, width: w, height: h) else {
                check("5x2: buffer created", false, "nil"); print("\n\(passed) passed, \(failed) failed"); if failed>0 {exit(1)}; return
            }
            var allMatch = true
            for y in 0..<h {
                for x in 0..<w {
                    let (b, g, r, a) = pixel(pb, x: x, y: y)
                    let i = (y * w + x) * 4
                    if b != src[i] || g != src[i+1] || r != src[i+2] || a != src[i+3] {
                        allMatch = false
                    }
                }
            }
            check("5x2: all pixels match (padding-safe)", allMatch)
        }

        // Case 3: undersized data → nil.
        do {
            let pb = RawVideoFrameSource.makeBGRA(from: Data(repeating: 0, count: 10), width: 4, height: 3)
            check("undersized: nil", pb == nil, "got buffer")
        }

        // Case 4: zero dims → nil.
        do {
            let pb = RawVideoFrameSource.makeBGRA(from: Data(), width: 0, height: 0)
            check("zero dims: nil", pb == nil, "got buffer")
        }

        // Case 5: realistic 320x180 round-trip (bigger, exercises memcpy bulk path).
        do {
            let w = 320, h = 180
            let src = sourceData(width: w, height: h)
            guard let pb = RawVideoFrameSource.makeBGRA(from: src, width: w, height: h) else {
                check("320x180: buffer created", false, "nil"); print("\n\(passed) passed, \(failed) failed"); if failed>0 {exit(1)}; return
            }
            // Sample a spread of pixels rather than all 57k for speed.
            let probes: [(Int, Int)] = [(0,0), (w-1,h-1), (w/2,h/2), (1,h-1), (w-1,0)]
            var allMatch = true
            for (x, y) in probes {
                let (b, g, r, a) = pixel(pb, x: x, y: y)
                let i = (y * w + x) * 4
                if b != src[i] || g != src[i+1] || r != src[i+2] || a != src[i+3] {
                    allMatch = false
                }
            }
            check("320x180: sampled pixels match", allMatch)
        }

        print("\n\(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}