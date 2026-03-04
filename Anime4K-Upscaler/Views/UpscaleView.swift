// Anime4K-Upscaler/Views/UpscaleView.swift
// Root NavigationSplitView layout for the Upscale feature tab.

import SwiftUI

struct UpscaleView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationSplitView {
            FileListView()
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
            if viewModel.files.isEmpty {
                EmptyStateView()
            } else {
                ConfigurationPanel()
            }
        case .processing:
            ProcessingView()
        }
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
            .help("Add video files")

            if !viewModel.files.isEmpty {
                Button {
                    viewModel.startProcessing()
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .help("Start processing")
                .disabled(!viewModel.canStartProcessing)
            }
        } else {
            if viewModel.engine.isProcessing {
                Button {
                    viewModel.cancelProcessing()
                } label: {
                    Label("Cancel", systemImage: "stop.fill")
                }
                .help("Cancel processing")
            } else {
                Button {
                    viewModel.returnToConfiguration()
                } label: {
                    Label("Done", systemImage: "checkmark")
                }
                .help("Return to configuration")
            }
        }
    }
}
