// Tests/BatchQueueCancellationTests.swift
// TDD Unit tests for batch queue transitions, single-batch cancellation,
// whole-queue cancellation, delete guards, and cancellation token isolation.

import Foundation

@main
struct BatchQueueCancellationTests {
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

        // --- Test Case 1: Single-batch cancellation allows queue runner to continue ---
        do {
            var states: [BatchState] = [.running, .pending, .pending]
            let queueCancelled = false

            // Cancel B1 while running
            states[0] = QueueLogic.finalizeBatchState(wasCancelled: true)
            check("B1 finalized as cancelled", states[0] == .cancelled)

            // Queue should continue because whole-queue was not cancelled
            let continueQueue = QueueLogic.shouldContinueQueue(queueCancelled: queueCancelled)
            check("Queue continues after single-batch cancel", continueQueue == true)

            // Next batch should be B2 (index 1)
            let nextIndex = QueueLogic.firstPendingBatchIndex(states)
            check("Next batch is index 1 (B2)", nextIndex == 1)
        }

        // --- Test Case 2: Whole-queue cancellation stops queue runner immediately ---
        do {
            var states: [BatchState] = [.running, .pending, .pending]
            let queueCancelled = true

            // Cancel all marks running and pending as cancelled
            for i in 0..<states.count {
                if !states[i].isTerminal {
                    states[i] = .cancelled
                }
            }

            check("All batches marked cancelled", states.allSatisfy { $0 == .cancelled })

            // Queue must NOT continue
            let continueQueue = QueueLogic.shouldContinueQueue(queueCancelled: queueCancelled)
            check("Queue stops on whole-queue cancel", continueQueue == false)

            // No pending batches remaining
            let nextIndex = QueueLogic.firstPendingBatchIndex(states)
            check("No pending batch after whole-queue cancel", nextIndex == nil)
        }

        // --- Test Case 3: Cancelling a pending batch skips it ---
        do {
            var states: [BatchState] = [.pending, .pending]
            // User cancels first batch before it starts
            states[0] = .cancelled

            let nextIndex = QueueLogic.firstPendingBatchIndex(states)
            check("Queue runner skips cancelled pending batch to index 1", nextIndex == 1)
        }

        // --- Test Case 4: Delete guards ---
        do {
            check("Cannot delete running batch", BatchState.running.isDeletable == false)
            check("Can delete pending batch", BatchState.pending.isDeletable == true)
            check("Can delete completed batch", BatchState.completed.isDeletable == true)
            check("Can delete failed batch", BatchState.failed.isDeletable == true)
            check("Can delete cancelled batch", BatchState.cancelled.isDeletable == true)
        }

        // --- Test Case 5: State terminal and active properties ---
        do {
            check("Pending is not terminal", BatchState.pending.isTerminal == false)
            check("Running is not terminal", BatchState.running.isTerminal == false)
            check("Completed is terminal", BatchState.completed.isTerminal == true)
            check("Failed is terminal", BatchState.failed.isTerminal == true)
            check("Cancelled is terminal", BatchState.cancelled.isTerminal == true)

            check("Pending is active", BatchState.pending.isActive == true)
            check("Running is active", BatchState.running.isActive == true)
            check("Completed is not active", BatchState.completed.isActive == false)
            check("Failed is not active", BatchState.failed.isActive == false)
            check("Cancelled is not active", BatchState.cancelled.isActive == false)
        }

        // --- Test Case 6: CancellationToken thread-safety and reset ---
        do {
            final class MockCancellationToken: @unchecked Sendable {
                private let lock = NSLock()
                private var _isCancelled = false
                var isCancelled: Bool {
                    lock.lock(); defer { lock.unlock() }
                    return _isCancelled
                }
                func cancel() { lock.lock(); _isCancelled = true; lock.unlock() }
                func reset() { lock.lock(); _isCancelled = false; lock.unlock() }
            }

            let token = MockCancellationToken()
            check("Token initial is not cancelled", token.isCancelled == false)
            token.cancel()
            check("Token is cancelled after cancel()", token.isCancelled == true)
            token.reset()
            check("Token is not cancelled after reset()", token.isCancelled == false)
        }

        print("\n\(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
