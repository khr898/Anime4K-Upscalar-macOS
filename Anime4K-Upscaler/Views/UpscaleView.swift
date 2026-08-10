// Anime4K-Upscaler/Views/UpscaleView.swift
// Root NavigationSplitView layout for the Upscale feature tab.
// Sidebar = batch queue; detail = staging (config + files + Add to Queue) when
// no batch is selected, or the selected batch's processing view.

import SwiftUI

struct UpscaleView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationSplitView {
            BatchQueueSidebar<UpscaleBatch>(
                items: viewModel.batches,
                selection: viewModel.selectedBatchID,
                onSelect: { viewModel.selectedBatchID = $0 },
                onCancel: { viewModel.cancelBatch(id: $0) },
                onDelete: { viewModel.deleteBatch(id: $0) },
                onNewBatch: { viewModel.returnToConfiguration() },
                summary: { batch in
                    "\(batch.configuration.mode.displayName) · \(batch.configuration.resolution.displayName) · \(batch.configuration.codec.displayName)"
                }
            )
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            detailView
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarButtons
            }
        }
        .alert("Missing Dependencies", isPresented: $viewModel.showDependencyAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The following bundled dependencies are missing:\n\n\(viewModel.dependencyErrors.joined(separator: "\n"))\n\nPlease rebuild the app to bundle all dependencies.")
        }
    }

    // MARK: - Detail View

    @ViewBuilder
    private var detailView: some View {
        switch viewModel.viewState {
        case .configuration:
            stagingView
        case .processing:
            ProcessingView()
        }
    }

    /// Staging detail: preset controls + staging file list + "Add to Queue".
    @ViewBuilder
    private var stagingView: some View {
        if viewModel.files.isEmpty && viewModel.batches.isEmpty {
            EmptyStateView()
        } else {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        ConfigurationPanel()
                        stagingFilesSection
                    }
                    .padding(16)
                }
                Divider()
                addToQueueFooter
            }
        }
    }

    @ViewBuilder
    private var stagingFilesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Staging (\(viewModel.files.count))")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.addFiles()
                } label: {
                    Label("Add Files", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            if viewModel.files.isEmpty {
                Text("No files staged. Add files to enqueue a batch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                FileListView()
                    .frame(minHeight: 120, maxHeight: 240)
            }
        }
    }

    private var addToQueueFooter: some View {
        HStack {
            if !viewModel.files.isEmpty {
                Text("\(viewModel.files.count) file\(viewModel.files.count == 1 ? "" : "s") ready")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                viewModel.enqueueBatch()
            } label: {
                Label("Add to Queue", systemImage: "plus.app")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(viewModel.files.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbarButtons: some View {
        if viewModel.viewState == .configuration {
            Button {
                viewModel.addFiles()
            } label: {
                Label("Add Files", systemImage: "plus")
            }
            .help("Add video files to staging")

            if !viewModel.files.isEmpty {
                Button {
                    viewModel.enqueueBatch()
                } label: {
                    Label("Add to Queue", systemImage: "plus.app")
                }
                .help("Enqueue a batch with the current preset")
            }

            if viewModel.canStartProcessing {
                Button {
                    viewModel.startProcessing()
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .help("Start processing the queue")
                .disabled(!viewModel.canStartProcessing)
            }
        } else {
            // Start must stay reachable after a batch is enqueued. enqueueBatch
            // sets selectedBatchID → viewState flips to .processing, which used
            // to hide the Start button (it lived only in the .configuration
            // branch above), leaving a pending batch stuck with no way to run
            // it and no running indication. Render it here whenever a pending
            // batch exists and the queue isn't already running.
            if viewModel.canStartProcessing {
                Button {
                    viewModel.startProcessing()
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .help("Start processing the queue")
            }
            if viewModel.isQueueProcessing {
                Button {
                    viewModel.cancelAllQueued()
                } label: {
                    Label("Cancel All", systemImage: "stop.fill")
                }
                .help("Cancel the whole queue")
            } else {
                Button {
                    viewModel.returnToConfiguration()
                } label: {
                    Label("New Batch", systemImage: "square.and.pencil")
                }
                .help("Return to staging")
            }
        }
    }
}