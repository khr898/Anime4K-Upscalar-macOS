// Anime4K-Upscaler/Anime4K_UpscalerApp.swift
// Application entry point.

import SwiftUI
import Foundation

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

    /// Add files to the active tab.
    private func addFilesToActiveTab() {
        switch viewModel.selectedMainTab {
        case .upscale:        viewModel.addFiles()
        case .compress:       compressVM.addFiles()
        case .streamOptimize: streamOptimizeVM.addFiles()
        }
    }

    /// Remove selected file in the active tab.
    private func removeSelectedFileInActiveTab() {
        switch viewModel.selectedMainTab {
        case .upscale:
            viewModel.removeSelectedFile()
        case .compress:
            if let id = compressVM.selectedFileID { compressVM.removeFile(id: id) }
        case .streamOptimize:
            if let id = streamOptimizeVM.selectedFileID { streamOptimizeVM.removeFile(id: id) }
        }
    }

    /// Remove all files in the active tab.
    private func removeAllFilesInActiveTab() {
        switch viewModel.selectedMainTab {
        case .upscale:        viewModel.removeAllFiles()
        case .compress:       compressVM.removeAllFiles()
        case .streamOptimize: streamOptimizeVM.removeAllFiles()
        }
    }

    /// Select output directory for the active tab.
    private func selectOutputDirectoryForActiveTab() {
        switch viewModel.selectedMainTab {
        case .upscale:        viewModel.selectOutputDirectory()
        case .compress:       compressVM.selectOutputDirectory()
        case .streamOptimize: streamOptimizeVM.selectDestinationDirectory()
        }
    }

    /// Start processing on the active tab.
    private func startProcessingActiveTab() {
        switch viewModel.selectedMainTab {
        case .upscale:        viewModel.startProcessing()
        case .compress:       compressVM.startProcessing()
        case .streamOptimize: streamOptimizeVM.startProcessing()
        }
    }

    private var activeTabHasSelectedFile: Bool {
        switch viewModel.selectedMainTab {
        case .upscale:        return viewModel.selectedFileID != nil
        case .compress:       return compressVM.selectedFileID != nil
        case .streamOptimize: return streamOptimizeVM.selectedFileID != nil
        }
    }

    private var activeTabHasFiles: Bool {
        switch viewModel.selectedMainTab {
        case .upscale:        return !viewModel.files.isEmpty
        case .compress:       return !compressVM.files.isEmpty
        case .streamOptimize: return !streamOptimizeVM.files.isEmpty
        }
    }

    private var activeTabCanStartProcessing: Bool {
        switch viewModel.selectedMainTab {
        case .upscale:        return viewModel.canStartProcessing
        case .compress:       return compressVM.canStartProcessing
        case .streamOptimize: return streamOptimizeVM.canStartProcessing
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
                    addFilesToActiveTab()
                }
                .keyboardShortcut("o", modifiers: .command)

                Divider()

                Button("Remove Selected File") {
                    removeSelectedFileInActiveTab()
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!activeTabHasSelectedFile)

                Button("Remove All Files") {
                    removeAllFilesInActiveTab()
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(!activeTabHasFiles)

                Divider()

                Button("Choose Output Directory…") {
                    selectOutputDirectoryForActiveTab()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }

            // Processing commands
            CommandMenu("Processing") {
                Button("Start Processing") {
                    startProcessingActiveTab()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!activeTabCanStartProcessing)

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
