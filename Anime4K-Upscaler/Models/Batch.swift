// Anime4K-Upscaler/Models/Batch.swift
// Generic queue batch: a frozen preset snapshot + the jobs built from a set of files
// (even a single file is a valid batch). Jobs are built at enqueue time so each
// batch carries a stable per-job reference (used by per-batch cancel and by the
// scoped processing view) and the preset cannot leak from later VM config edits.
//
// Pure decision logic (BatchState + QueueLogic) lives in BatchState.swift and is
// unit-tested standalone; this class is the @MainActor @Observable wrapper used by
// the three view-model queue runners.

import Foundation
import Observation

/// One entry in a tab's batch queue. Generic over the tab's frozen configuration
/// type and job class so all three tabs share one definition without a shared
/// pipeline protocol.
@MainActor @Observable
final class Batch<Config: Sendable & Equatable, Job: AnyObject & Identifiable>: Identifiable {

    let id: UUID
    /// Frozen preset snapshot — mutations to the VM's live config after enqueue
    /// do not affect this batch.
    let configuration: Config
    /// Frozen output directory snapshot at enqueue time; lets different batches
    /// target different directories.
    let outputDirectory: URL?
    let createdAt: Date

    /// Jobs built from the staging files at enqueue. The runner mutates each job's
    /// `state` (queued -> running -> terminal); the files are reachable via
    /// `jobs.map(\.file)`.
    var jobs: [Job]

    var state: BatchState = .pending
    var startedAt: Date?
    var finishedAt: Date?

    init(id: UUID = UUID(),
         configuration: Config,
         outputDirectory: URL?,
         jobs: [Job],
         createdAt: Date = Date()) {
        self.id = id
        self.configuration = configuration
        self.outputDirectory = outputDirectory
        self.jobs = jobs
        self.createdAt = createdAt
    }

    /// Number of source files in this batch.
    var fileCount: Int { jobs.count }

    /// Whether the batch may be deleted from the queue (never the running one).
    var isDeletable: Bool { QueueLogic.canDeleteBatch(state: state) }
}

// MARK: - Tab-specific aliases

typealias UpscaleBatch = Batch<JobConfiguration, ProcessingJob>
typealias CompressBatch = Batch<CompressConfiguration, CompressJob>
typealias StreamOptimizeBatch = Batch<StreamOptimizeConfiguration, StreamOptimizeJob>