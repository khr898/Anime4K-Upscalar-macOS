// Anime4K-Upscaler/Views/Detail/ProcessingView.swift
// Live processing dashboard with per-file progress and log output.

import SwiftUI

struct ProcessingView: View {
    @Environment(AppViewModel.self) private var viewModel

    @State private var selectedJobID: UUID?
    @State private var showLog: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            processingHeader

            Divider()

            // Job list
            jobList

            Divider()

            // Log panel (expandable)
            if showLog, let job = selectedJob {
                logPanel(job: job)
            }

            Divider()

            // Footer
            processingFooter
        }
        .background(.background)
        .onAppear {
            selectedJobID = viewModel.jobs.first?.id
        }
    }

    // MARK: - Header

    private var processingHeader: some View {
        VStack(spacing: 8) {
            HStack {
                if viewModel.engine.isProcessing {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 2)
                } else if viewModel.allJobsFinished {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                Text(headerTitle)
                    .font(.headline)

                Spacer()

                Text("\(viewModel.engine.currentJobIndex)/\(viewModel.engine.totalJobs)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }

            // Overall progress
            ProgressView(value: viewModel.engine.overallProgress, total: 1.0)
                .progressViewStyle(.linear)
                .tint(viewModel.allJobsFinished ? .green : .blue)

            // Config summary
            HStack(spacing: 16) {
                configBadge(icon: "wand.and.stars", text: viewModel.configuration.mode.displayName)
                configBadge(icon: "arrow.up.left.and.arrow.down.right", text: viewModel.configuration.resolution.displayName)
                configBadge(icon: viewModel.configuration.codec.symbolName, text: viewModel.configuration.codec.displayName)
                Spacer()
            }
        }
        .padding(16)
    }

    private var headerTitle: String {
        if viewModel.allJobsFinished {
            let failed = viewModel.failedJobCount
            if failed > 0 {
                return "Completed with \(failed) error\(failed == 1 ? "" : "s")"
            }
            return "All Tasks Completed"
        }
        return "Processing..."
    }

    private func configBadge(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .foregroundStyle(.secondary)
    }

    // MARK: - Job List

    private var jobList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(viewModel.jobs) { job in
                    ProgressRow(job: job)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedJobID == job.id ? Color.blue.opacity(0.06) : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedJobID = job.id
                        }
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Log Panel

    private func logPanel(job: ProcessingJob) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Log Output", systemImage: "terminal")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    job.logLines.removeAll()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear log")
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(job.logLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .frame(height: 120)
                .background(Color(.textBackgroundColor).opacity(0.5))
                .onChange(of: job.logLines.count) {
                    if let last = job.logLines.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var processingFooter: some View {
        HStack(spacing: 12) {
            // Log toggle
            Button {
                showLog.toggle()
            } label: {
                Label(showLog ? "Hide Log" : "Show Log", systemImage: "terminal")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            // Stats
            if viewModel.allJobsFinished {
                HStack(spacing: 8) {
                    Label("\(viewModel.completedJobCount) completed", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)

                    if viewModel.failedJobCount > 0 {
                        Label("\(viewModel.failedJobCount) failed", systemImage: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            // Action buttons
            if viewModel.engine.isProcessing {
                Button {
                    viewModel.cancelProcessing()
                } label: {
                    Label("Cancel All", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
            } else if viewModel.allJobsFinished {
                Button {
                    viewModel.returnToConfiguration()
                } label: {
                    Label("Done", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private var selectedJob: ProcessingJob? {
        guard let id = selectedJobID else { return viewModel.jobs.first }
        return viewModel.jobs.first(where: { $0.id == id })
    }
}
