// Anime4K-Upscaler/Models/BatchState.swift
// Pure-Foundation batch-queue logic with no SwiftUI / @MainActor dependencies so it
// can be unit-tested standalone via swiftc (see Tests/BatchQueueLogicTests.swift).
// The @MainActor @Observable Batch<Config,Job> class lives in Batch.swift and wraps
// these helpers for the live view-model queue runners.

import Foundation

/// Lifecycle state of a queue batch. Distinct from `JobState` — a batch's state is
/// driven by the queue runner's intent (enqueue / run / cancel), not by aggregating
/// per-job states. A batch is `.completed` when the runner finishes iterating its
/// jobs regardless of individual job failures (matches pre-queue behavior; per-job
/// state carries failure detail).
enum BatchState: String, Sendable, CaseIterable {
    case pending     // queued, not yet started
    case running     // currently executing its jobs
    case completed   // runner finished iterating the batch's jobs
    case failed      // reserved; not assigned by current runner policy
    case cancelled   // user cancelled (per-batch or cancel-all)

    /// True for completed / failed / cancelled — the runner and sidebar treat these
    /// as done (no further execution, deletable).
    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled: return true
        case .pending, .running: return false
        }
    }

    /// True for states that are still in flight or awaiting execution. Used by the
    /// sidebar to show the cancel affordance (pending | running).
    var isActive: Bool {
        switch self {
        case .pending, .running: return true
        case .completed, .failed, .cancelled: return false
        }
    }
}

/// Framework-free queue decision helpers. Kept pure (value in, value out) so the
/// three VM queue runners can stay thin and the logic is testable without spawning
/// FFmpeg or depending on SwiftUI / IOKit.
enum QueueLogic {
    /// Index of the first `.pending` batch in enqueue order, or nil if none pending.
    /// The runner re-reads this every loop turn so a batch appended mid-run
    /// (add-while-running) is picked up.
    static func firstPendingBatchIndex(_ states: [BatchState]) -> Int? {
        states.firstIndex(where: { $0 == .pending })
    }

    /// Final state to assign a batch after its jobs finish running. Locked policy:
    /// `.completed` on finish regardless of individual job failures; `.cancelled`
    /// only when the batch was cancelled (per-batch or whole-queue).
    static func finalizeBatchState(wasCancelled: Bool) -> BatchState {
        wasCancelled ? .cancelled : .completed
    }

    /// Whether the queue runner should loop to the next batch. Stops only when the
    /// whole queue was cancelled (per-batch cancel lets the queue continue).
    static func shouldContinueQueue(queueCancelled: Bool) -> Bool {
        !queueCancelled
    }

    /// Whether a staging set can be enqueued as a batch. A single file is a valid
    /// batch (degenerate case explicitly required).
    static func canEnqueue(fileCount: Int) -> Bool {
        fileCount > 0
    }

    /// Whether a batch may be deleted from the queue. The running batch is never
    /// deletable (use cancel instead); pending and terminal batches are.
    static func canDeleteBatch(state: BatchState) -> Bool {
        state != .running
    }
}