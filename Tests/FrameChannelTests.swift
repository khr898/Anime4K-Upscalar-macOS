// Tests/FrameChannelTests.swift
// Standalone assert-based self-check for the Phase 4 ring buffer.
// Pure value-type core (BoundedFIFO) is deterministically testable; the
// blocking FrameChannel wrapper is a thin NSCondition coat over it.
// Compile + run outside Xcode (pure Foundation):
//   swiftc Anime4K-Upscaler/Utilities/FrameChannel.swift Tests/FrameChannelTests.swift \
//          -o /tmp/fchtest && /tmp/fchtest
//
// What this proves:
//   - FIFO order: frames pop in the same order they were pushed (strict PTS).
//   - Capacity bound: a push past capacity is rejected (backpressure / no unbounded growth).
//   - Close drains: after close, remaining frames still pop; then pop returns nil (EOF).
//   - Push after close is a no-op (producer can't revive a closed channel).
//   - Empty pop is nil (never blocks the non-blocking API on empty).

import Foundation

@main
struct FrameChannelTests {
    static func main() {
        var passed = 0
        var failed = 0
        func check(_ name: String, _ condition: Bool, _ detail: String = "") {
            if condition { print("PASS: \(name)"); passed += 1 }
            else { print("FAIL: \(name) \(detail)"); failed += 1 }
        }

        // --- BoundedFIFO: pure value-type core ---
        do {
            var f = BoundedFIFO<Int>(capacity: 3)
            check("empty pop nil", f.tryPop() == nil)
            check("empty isEmpty", f.isEmpty)
            check("not full when empty", !f.isFull)
            check("push A ok", f.tryPush(1) == true)
            check("push B ok", f.tryPush(2) == true)
            check("push C ok", f.tryPush(3) == true)
            check("full at capacity", f.isFull)
            check("push D rejected (capacity 3)", f.tryPush(4) == false)
            check("count is 3", f.count == 3)
            // FIFO order preserved.
            check("pop A", f.tryPop() == 1)
            check("pop B", f.tryPop() == 2)
            check("pop C", f.tryPop() == 3)
            check("empty after drain", f.isEmpty)
            // After draining, room again.
            check("push E ok after drain", f.tryPush(5) == true)
            check("pop E", f.tryPop() == 5)
        }

        // --- Close drains remaining, then nil; push after close no-op ---
        do {
            var f = BoundedFIFO<String>(capacity: 4)
            _ = f.tryPush("a")
            _ = f.tryPush("b")
            check("open: not closed", !f.closed)
            f.close()
            check("closed flag set", f.closed)
            // Push after close is a no-op.
            check("push after close rejected", f.tryPush("c") == false)
            // Remaining frames still drain in order.
            check("drain a", f.tryPop() == "a")
            check("drain b", f.tryPop() == "b")
            check("pop after drain + closed = nil", f.tryPop() == nil)
        }

        // --- Capacity 1 (degenerate but valid) ---
        do {
            var f = BoundedFIFO<Int>(capacity: 1)
            check("cap1 push ok", f.tryPush(7) == true)
            check("cap1 full", f.isFull)
            check("cap1 second push rejected", f.tryPush(8) == false)
            check("cap1 pop", f.tryPop() == 7)
            check("cap1 empty", f.isEmpty)
        }

        // --- FrameChannel: thread-safe blocking wrapper, FIFO across threads ---
        // Producer pushes 1000 ints from one queue; consumer pops them on another.
        // Verifies (a) all 1000 arrive (no drops), (b) strict FIFO order, (c) close
        // lets the consumer exit cleanly.
        do {
            let ch = FrameChannel<Int>(capacity: 4)
            let n = 1000
            let producerQueue = DispatchQueue(label: "test.producer")
            let consumerQueue = DispatchQueue(label: "test.consumer")
            var received: [Int] = []
            let lock = NSLock()

            let consumerDone = DispatchSemaphore(value: 0)
            consumerQueue.async {
                while let v = ch.pop() { lock.lock(); received.append(v); lock.unlock() }
                consumerDone.signal()
            }
            producerQueue.async {
                for i in 0..<n { ch.push(i) }
                ch.close()
            }
            consumerDone.wait()

            lock.lock(); let r = received; lock.unlock()
            check("channel delivered all \(n)", r.count == n, "got \(r.count)")
            check("channel FIFO order 0..n-1", r == Array(0..<n))
            check("channel pop after close+drain = nil", ch.pop() == nil)
        }

        // --- FrameChannel: capacity bound backpressures producer ---
        // With a slow consumer (never pops), the producer can push only `capacity`
        // frames before blocking; close unblocks it so the test doesn't hang.
        do {
            let ch = FrameChannel<Int>(capacity: 2)
            let pushed = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                _ = ch.push(1); _ = ch.push(2); _ = ch.push(3)  // 3rd blocks (cap 2)
                pushed.signal()                                  // only reached after unblock
                ch.close()
            }
            // Producer's 3rd push is blocked → signal NOT fired within 200ms.
            check("producer blocked at capacity (no early signal)", pushed.wait(timeout: .now() + 0.2) == .timedOut)
            // Drain two → unblocks the 3rd push.
            check("pop 1", ch.pop() == 1)
            check("pop 2", ch.pop() == 2)
            // Now the 3rd push completes; close fires the signal.
            check("producer unblocked after drain", pushed.wait(timeout: .now() + 1.0) == .success)
            check("pop 3 (the unblocked push)", ch.pop() == 3)
            check("channel drained nil", ch.pop() == nil)
        }

        print("\n\(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}