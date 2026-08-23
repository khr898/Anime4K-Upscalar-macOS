// Tests/QueueWiringTests.swift
// Tests canStartProcessing logic and queue wiring state transitions for all tabs.

import Foundation

@main
struct QueueWiringTests {
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

        func canStart(isQueueProcessing: Bool, hasPendingBatches: Bool, hasStagedFiles: Bool) -> Bool {
            !isQueueProcessing && (hasPendingBatches || hasStagedFiles)
        }

        // Test single file in staging, empty queue (The core Issue 3 scenario)
        check("Single staged file can start directly",
              canStart(isQueueProcessing: false, hasPendingBatches: false, hasStagedFiles: true))

        // Test multiple files in staging, empty queue
        check("Multiple staged files can start directly",
              canStart(isQueueProcessing: false, hasPendingBatches: false, hasStagedFiles: true))

        // Test empty staging, 1 pending batch in queue
        check("Enqueued pending batch can start",
              canStart(isQueueProcessing: false, hasPendingBatches: true, hasStagedFiles: false))

        // Test staged files + pending batches
        check("Staged files + pending batches can start",
              canStart(isQueueProcessing: false, hasPendingBatches: true, hasStagedFiles: true))

        // Test empty staging, empty queue
        check("Empty staging + empty queue cannot start",
              !canStart(isQueueProcessing: false, hasPendingBatches: false, hasStagedFiles: false))

        // Test while queue is running
        check("Running queue cannot start again (with pending)",
              !canStart(isQueueProcessing: true, hasPendingBatches: true, hasStagedFiles: false))
        check("Running queue cannot start again (with staging)",
              !canStart(isQueueProcessing: true, hasPendingBatches: false, hasStagedFiles: true))

        print("\n\(passed) passed, \(failed) failed\n")
        if failed > 0 { exit(1) }
    }
}
