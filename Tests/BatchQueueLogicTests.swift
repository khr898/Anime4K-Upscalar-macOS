// Tests/BatchQueueLogicTests.swift
// Standalone assert-based self-check for the pure queue logic.
// Compile + run outside Xcode:
//   swiftc Anime4K-Upscaler/Models/BatchState.swift \
//          Tests/BatchQueueLogicTests.swift -o /tmp/bqltest && /tmp/bqltest
// No Swift Testing / SPM dependency — pure Foundation, runnable anywhere swiftc is.
// Tests the framework-free half of the batch-queue feature (BatchState + QueueLogic).
// The @MainActor @Observable Batch<Config,Job> class and the three VM queue runners
// depend on SwiftUI/IOKit/AVFoundation and are covered by build + manual smoke.

import Foundation

@main
struct BatchQueueLogicTests {
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

        // --- BatchState.isTerminal ---
        check("pending not terminal", !BatchState.pending.isTerminal)
        check("running not terminal", !BatchState.running.isTerminal)
        check("completed terminal", BatchState.completed.isTerminal)
        check("failed terminal", BatchState.failed.isTerminal)
        check("cancelled terminal", BatchState.cancelled.isTerminal)

        // --- BatchState.isActive (running or pending) ---
        check("pending active", BatchState.pending.isActive)
        check("running active", BatchState.running.isActive)
        check("completed not active", !BatchState.completed.isActive)
        check("cancelled not active", !BatchState.cancelled.isActive)

        // --- QueueLogic.firstPendingBatchIndex ---
        check("empty queue -> nil", QueueLogic.firstPendingBatchIndex([]) == nil)
        check("all pending -> 0",
              QueueLogic.firstPendingBatchIndex([.pending, .pending, .pending]) == 0)
        check("skips terminal -> first pending index",
              QueueLogic.firstPendingBatchIndex([.completed, .cancelled, .pending, .running]) == 2)
        check("skips running -> next pending",
              QueueLogic.firstPendingBatchIndex([.running, .pending]) == 1)
        check("no pending -> nil",
              QueueLogic.firstPendingBatchIndex([.running, .completed, .cancelled]) == nil)

        // --- QueueLogic.finalizeBatchState (after a batch's jobs finish running) ---
        // Locked decision: batch is .completed on finish regardless of individual job
        // failures; .cancelled only when the batch was cancelled (queue or per-batch).
        check("finished not cancelled -> completed",
              QueueLogic.finalizeBatchState(wasCancelled: false) == .completed)
        check("finished cancelled -> cancelled",
              QueueLogic.finalizeBatchState(wasCancelled: true) == .cancelled)

        // --- QueueLogic.shouldContinueQueue ---
        // Continue to next batch unless the whole queue was cancelled.
        check("queue not cancelled -> continue",
              QueueLogic.shouldContinueQueue(queueCancelled: false) == true)
        check("queue cancelled -> stop",
              QueueLogic.shouldContinueQueue(queueCancelled: true) == false)

        // --- QueueLogic.canEnqueue (single file is a valid batch) ---
        check("one file enqueueable", QueueLogic.canEnqueue(fileCount: 1))
        check("zero files not enqueueable", !QueueLogic.canEnqueue(fileCount: 0))
        check("many files enqueueable", QueueLogic.canEnqueue(fileCount: 5))

        // --- QueueLogic.canDeleteBatch (never the running one) ---
        check("can delete pending", QueueLogic.canDeleteBatch(state: .pending))
        check("cannot delete running", !QueueLogic.canDeleteBatch(state: .running))
        check("can delete completed", QueueLogic.canDeleteBatch(state: .completed))
        check("can delete cancelled", QueueLogic.canDeleteBatch(state: .cancelled))

        print("\n\(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}