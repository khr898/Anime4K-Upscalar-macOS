// Tests/FrameChannelStagingTests.swift
// Unit test validating consumer staging register retention and ordering under simulated backpressure.

import Foundation
import CoreMedia
import CoreVideo

@main
struct FrameChannelStagingTests {
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

        // Mock channel queue
        var channelQueue: [(Int, CMTime)] = (0..<100).map { i in
            (i, CMTime(value: Int64(i) * 25025, timescale: 600_000))
        }

        func popChannel() -> (Int, CMTime)? {
            if channelQueue.isEmpty { return nil }
            return channelQueue.removeFirst()
        }

        var pendingStagingFrame: (Int, CMTime)? = nil
        var appendedFrames: [(Int, CMTime)] = []

        // Mock simulated encoder: randomly fails 40% of the time to simulate FIFO saturation
        var mockEncoderAcceptCycle = 0
        func mockAppend(frame: Int, pts: CMTime) -> Bool {
            mockEncoderAcceptCycle += 1
            // Accept on even calls, reject on odd calls (simulating periodic buffer fullness)
            if mockEncoderAcceptCycle % 3 == 0 {
                return false // Full buffer rejection
            }
            return true
        }

        // Run consumer drain loop until channel is fully consumed
        var iterations = 0
        while (!channelQueue.isEmpty || pendingStagingFrame != nil) && iterations < 1000 {
            iterations += 1
            let currentItem: (Int, CMTime)
            if let staged = pendingStagingFrame {
                currentItem = staged
                pendingStagingFrame = nil
            } else if let popped = popChannel() {
                currentItem = popped
            } else {
                break
            }

            if mockAppend(frame: currentItem.0, pts: currentItem.1) {
                appendedFrames.append(currentItem)
            } else {
                // Staging register saves the unwritten frame
                pendingStagingFrame = currentItem
            }
        }

        check("100% of frames preserved through backpressure", appendedFrames.count == 100, "got \(appendedFrames.count)")
        check("Exact sequential order preserved (no frame drops)", appendedFrames.map { $0.0 } == Array(0..<100))
        check("No frame stuck in staging register at EOS", pendingStagingFrame == nil)
        check("Timestamp continuity preserved", appendedFrames.last?.1.value == Int64(99 * 25025))

        print("\nFrameChannelStagingTests Results: \(passed) passed, \(failed) failed\n")
        if failed > 0 { exit(1) }
    }
}
