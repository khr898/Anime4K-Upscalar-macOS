// Anime4K-Upscaler/Anime4K_UpscalerApp.swift
// Application entry point.

import SwiftUI

@main
struct Anime4K_UpscalerApp: App {
    @State private var viewModel = AppViewModel()
    @State private var compressVM = CompressViewModel()
    @State private var streamOptimizeVM = StreamOptimizeViewModel()

    /// True if the currently-active tab's queue is processing.
    private var activeTabIsQueueProcessing: Bool {
        switch viewModel.selectedMainTab {
        case .upscale:        return viewModel.isQueueProcessing
        case .compress:       return compressVM.isQueueProcessing
        case .streamOptimize: return streamOptimizeVM.isQueueProcessing
        }
    }

    /// Cancel only the active tab's queue (locked decision: app-level cancel is
    /// per-tab, not global).
    private func cancelActiveTabQueue() {
        switch viewModel.selectedMainTab {
        case .upscale:        viewModel.cancelAllQueued()
        case .compress:       compressVM.cancelAllQueued()
        case .streamOptimize: streamOptimizeVM.cancelAllQueued()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(viewModel)
                .environment(compressVM)
                .environment(streamOptimizeVM)
                .frame(minWidth: 860, minHeight: 540)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    SecurityScopeManager.shared.stopAccessingAll()
                }
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            // File menu commands
            CommandGroup(after: .newItem) {
                Button("Add Video Files...") {
                    viewModel.addFiles()
                }
                .keyboardShortcut("o", modifiers: .command)

                Divider()

                Button("Remove Selected File") {
                    viewModel.removeSelectedFile()
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(viewModel.selectedFileID == nil)

                Button("Remove All Files") {
                    viewModel.removeAllFiles()
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(viewModel.files.isEmpty)

                Divider()

                Button("Choose Output Directory…") {
                    viewModel.selectOutputDirectory()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }

            // Processing commands
            CommandMenu("Processing") {
                Button("Start Processing") {
                    viewModel.startProcessing()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!viewModel.canStartProcessing)

                Button("Cancel Processing") {
                    cancelActiveTabQueue()
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!activeTabIsQueueProcessing)

                Divider()

                Button("Return to Configuration") {
                    viewModel.returnToConfiguration()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(activeTabIsQueueProcessing || viewModel.viewState == .configuration)
            }
        }
    }
}
