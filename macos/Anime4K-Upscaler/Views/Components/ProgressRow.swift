// Anime4K-Upscaler/Views/Components/ProgressRow.swift
// Single file progress row for the processing view.

import SwiftUI

struct ProgressRow: View {
    var job: ProcessingJob

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // File name and state
            HStack {
                Image(systemName: job.state.symbolName)
                    .font(.body)
                    .foregroundStyle(job.state.tintColor)
                    .frame(width: 20)
                    .symbolEffect(.pulse, isActive: job.state == .running)

                Text(job.file.fileName)
                    .font(.system(.body, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                stateLabel
            }

            // Progress bar (only when running or completed)
            if job.state == .running || job.state == .completed {
                ProgressView(value: job.progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(job.state == .completed ? .green : .blue)

                // Stats row
                HStack(spacing: 12) {
                    statItem(label: "Progress", value: "\(Int(job.progress * 100))%")
                    statItem(label: "Frame", value: "\(job.currentFrame)")
                    statItem(label: "FPS", value: job.fps)
                    statItem(label: "Speed", value: job.speed)

                    Spacer()

                    if let elapsed = job.formattedElapsedTime {
                        statItem(label: "Elapsed", value: elapsed)
                    }
                }
            }

            // Error message
            if let error = job.errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }

    // MARK: - State Label

    @ViewBuilder
    private var stateLabel: some View {
        switch job.state {
        case .idle:
            Text("Ready")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .queued:
            Text("Queued")
                .font(.caption)
                .foregroundStyle(.orange)
        case .running:
            Text("\(Int(job.progress * 100))%")
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(.blue)
        case .completed:
            Text("Done")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.green)
        case .failed:
            Text("Failed")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.red)
        case .cancelled:
            Text("Cancelled")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.yellow)
        }
    }

    // MARK: - Stat Item

    private func statItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.quaternary)
                .textCase(.uppercase)
            Text(value)
                .font(.caption2)
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
