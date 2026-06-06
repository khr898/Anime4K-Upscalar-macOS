// Anime4K-Upscaler/Views/Sidebar/FileListView.swift
// Sidebar file list with drag-and-drop support.

import SwiftUI
import UniformTypeIdentifiers

struct FileListView: View {
    @Environment(AppViewModel.self) private var viewModel

    @State private var isDropTargeted: Bool = false

    var body: some View {
        @Bindable var viewModel = viewModel
        VStack(spacing: 0) {
            // Header
            fileListHeader

            Divider()

            // File list or drop zone
            if viewModel.files.isEmpty {
                dropZonePlaceholder
            } else {
                fileList
            }

            Divider()

            // Footer summary
            fileListFooter
        }
        .background(.background)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    // MARK: - Header

    private var fileListHeader: some View {
        HStack {
            Label("Files", systemImage: "film.stack")
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()

            if !viewModel.files.isEmpty {
                Text("\(viewModel.files.count)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - File List

    @ViewBuilder
    private var fileList: some View {
        @Bindable var viewModel = viewModel
        List(selection: $viewModel.selectedFileID) {
            ForEach(viewModel.files) { file in
                FileRow(file: file)
                    .tag(file.id)
                    .contextMenu {
                        Button("Remove", role: .destructive) {
                            viewModel.removeFile(id: file.id)
                        }
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([file.url])
                        }
                    }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if isDropTargeted {
                dropOverlay
            }
        }
    }

    // MARK: - Drop Zone Placeholder

    private var dropZonePlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "arrow.down.doc")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)

            Text("Drop Video Files Here")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("or click + to browse")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.blue.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .padding(8)
            }
        }
    }

    // MARK: - Drop Overlay

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.blue.opacity(0.08))
            .strokeBorder(.blue.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [8]))
            .padding(4)
    }

    // MARK: - Footer

    private var fileListFooter: some View {
        HStack(spacing: 8) {
            if !viewModel.files.isEmpty {
                Text(viewModel.totalFileSize)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let dur = viewModel.totalDuration {
                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                    Text(dur)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    viewModel.removeAllFiles()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove all files")
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Drop Handling

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var didAdd = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil, isAbsolute: true) else {
                        return
                    }

                    let ext = url.pathExtension.lowercased()
                    guard SupportedVideoExtension.allExtensions.contains(ext) else { return }

                    Task { @MainActor in
                        viewModel.addFilesFromDrop([url])
                    }
                }
                didAdd = true
            }
        }

        return didAdd
    }
}

// MARK: - File Row

struct FileRow: View {
    let file: VideoFile

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "film")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.fileName)
                    .font(.system(.body, design: .default))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 4) {
                    Text(file.fileExtension.uppercased())
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.blue.opacity(0.12))
                        .foregroundStyle(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    Text(file.formattedFileSize)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if let res = file.resolutionString {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                        Text(res)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if let dur = file.formattedDuration {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                        Text(dur)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}
