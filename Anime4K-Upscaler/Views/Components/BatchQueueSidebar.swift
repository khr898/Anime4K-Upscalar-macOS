// Anime4K-Upscaler/Views/Components/BatchQueueSidebar.swift
// Shared left-sidebar queue list for all three tabs. Generic over the tab's batch
// type (which conforms to BatchItemLike). Closures-based to avoid protocol/
// associated-type churn in views — each tab passes its VM's batches + callbacks
// + a tab-specific summary closure.
//
// Layout (per the approved "queue replaces file list" mock):
//   ┌───────────────┐
//   │ QUEUE         │
//   │ ▶ Batch 1     │  state dot + preset summary + file count
//   │   3 files     │  [cancel] [delete]  (cancel: pending|running; delete: not running)
//   │ ▶ Batch 2     │
//   │ + New Batch   │  sets selectedBatchID = nil (staging detail)
//   └───────────────┘

import SwiftUI

/// Minimal shape a batch type exposes to the sidebar. `Batch<Config,Job>` conforms
/// via an extension below.
protocol BatchItemLike: AnyObject, Identifiable {
    var state: BatchState { get }
    var fileCount: Int { get }
}

extension Batch: BatchItemLike {}

/// SwiftUI-side presentation for `BatchState`. Kept here (not in the pure
/// BatchState.swift) so BatchState stays Foundation-only and standalone-testable.
extension BatchState {
    var displayName: String {
        switch self {
        case .pending:    return "Pending"
        case .running:    return "Processing"
        case .completed:  return "Completed"
        case .failed:     return "Failed"
        case .cancelled:  return "Cancelled"
        }
    }

    var symbolName: String {
        switch self {
        case .pending:    return "clock"
        case .running:    return "circle.dashed"
        case .completed:  return "checkmark.circle.fill"
        case .failed:     return "xmark.circle.fill"
        case .cancelled:  return "stop.circle.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .pending:    return .orange
        case .running:    return .blue
        case .completed:  return .green
        case .failed:     return .red
        case .cancelled:  return .yellow
        }
    }
}

/// Generic queue sidebar. `Item` is the tab's batch type (e.g. `UpscaleBatch`).
struct BatchQueueSidebar<Item: BatchItemLike>: View where Item.ID == UUID {
    let items: [Item]
    let selection: UUID?
    let onSelect: (UUID?) -> Void
    let onCancel: (UUID) -> Void
    let onDelete: (UUID) -> Void
    let onNewBatch: () -> Void
    var onStartQueue: (() -> Void)? = nil
    /// Tab-specific preset summary, e.g. "Mode A · 2x · HEVC".
    let summary: (Item) -> String

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Queue")
                    .font(.headline)
                Spacer()
                Text("\(items.count) batch\(items.count == 1 ? "" : "es")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if items.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "tray")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No batches queued")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Add files + set a preset, then “Add to Queue”.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 16)
                Spacer()
            } else {
                List(selection: Binding(
                    get: { selection },
                    set: { onSelect($0) }
                )) {
                    ForEach(items) { item in
                        BatchRow(
                            item: item,
                            summary: summary(item),
                            onCancel: { onCancel(item.id) },
                            onDelete: { onDelete(item.id) }
                        )
                        .tag(item.id)
                    }
                }
                .listStyle(.sidebar)
            }

            Divider()

            // Footer with New Batch and optional Start Queue
            HStack {
                Button {
                    onNewBatch()
                } label: {
                    Label("New Batch", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)

                Spacer()

                if let onStartQueue, items.contains(where: { $0.state == .pending }) {
                    Button {
                        onStartQueue()
                    } label: {
                        Label("Start Queue", systemImage: "play.fill")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(selection == nil ? Color.accentColor.opacity(0.08) : Color.clear)
        }
    }
}

/// One queue row: state dot, preset summary, file count, cancel + delete buttons.
private struct BatchRow<Item: BatchItemLike>: View where Item.ID == UUID {
    let item: Item
    let summary: String
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.state.symbolName)
                .foregroundStyle(item.state.tintColor)
                .font(.caption)

            VStack(alignment: .leading, spacing: 2) {
                Text(summary)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text("\(item.fileCount) file\(item.fileCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if item.state.isActive {
                Button(action: onCancel) {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .help("Cancel this batch")
            }
            if item.state != .running {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remove from queue")
            }
        }
        .padding(.vertical, 2)
    }
}