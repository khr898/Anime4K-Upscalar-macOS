// Anime4K-Upscaler/Views/Compress/CompressView.swift
// Complete Compress feature UI — file list, configuration, processing.

import SwiftUI
import UniformTypeIdentifiers

struct CompressView: View {
    @Environment(CompressViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationSplitView {
            CompressFileListView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            switch viewModel.viewState {
            case .configuration:
                if viewModel.files.isEmpty {
                    CompressEmptyStateView()
                } else {
                    CompressConfigPanel()
                }
            case .processing:
                CompressProcessingView()
            }
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                compressToolbarButtons
            }
        }
    }

    @ViewBuilder
    private var compressToolbarButtons: some View {
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
                    Label("Compress", systemImage: "play.fill")
                }
                .help("Start compression")
                .disabled(!viewModel.canStartProcessing)
            }
        } else {
            if viewModel.isProcessing {
                Button {
                    viewModel.cancelProcessing()
                } label: {
                    Label("Cancel", systemImage: "stop.fill")
                }
                .help("Cancel compression")
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

// MARK: - Empty State

private struct CompressEmptyStateView: View {
    @Environment(CompressViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "archivebox")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
                .symbolEffect(.pulse, options: .repeating.speed(0.3))

            Text("Compress Videos")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Add video files to compress with visually lossless quality")
                .font(.body)
                .foregroundStyle(.secondary)

            Button {
                viewModel.addFiles()
            } label: {
                Label("Add Files", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                featureRow(symbol: "bolt.fill", text: "HEVC Hardware or SVT-AV1 Software encoding")
                featureRow(symbol: "slider.horizontal.3", text: "Customizable quality with smart defaults")
                featureRow(symbol: "sparkles.tv", text: "Anime-optimized B-Frames & Long GOP")
                featureRow(symbol: "sun.max", text: "Auto HDR10 detection and pass-through")
            }
            .padding(.top, 8)
            .padding(.horizontal, 40)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private func featureRow(symbol: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(width: 18)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - File List Sidebar

private struct CompressFileListView: View {
    @Environment(CompressViewModel.self) private var viewModel
    @State private var isDropTargeted: Bool = false

    var body: some View {
        @Bindable var viewModel = viewModel
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Files", systemImage: "film.stack")
                    .font(.headline)
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

            Divider()

            if viewModel.files.isEmpty {
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
                            .strokeBorder(.orange.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [8]))
                            .padding(8)
                    }
                }
            } else {
                List(selection: $viewModel.selectedFileID) {
                    ForEach(viewModel.files) { file in
                        CompressFileRow(file: file)
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
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.orange.opacity(0.08))
                            .strokeBorder(.orange.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [8]))
                            .padding(4)
                    }
                }
            }

            Divider()

            // Footer
            HStack(spacing: 8) {
                if !viewModel.files.isEmpty {
                    Text(viewModel.totalFileSize)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let dur = viewModel.totalDuration {
                        Text("•").font(.caption2).foregroundStyle(.quaternary)
                        Text(dur).font(.caption2).foregroundStyle(.secondary)
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
        .background(.background)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var didAdd = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil, isAbsolute: true) else { return }
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

private struct CompressFileRow: View {
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
                        .background(.orange.opacity(0.12))
                        .foregroundStyle(.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    Text(file.formattedFileSize)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if let res = file.resolutionString {
                        Text("•").font(.caption2).foregroundStyle(.quaternary)
                        Text(res).font(.caption2).foregroundStyle(.tertiary)
                    }

                    if let dur = file.formattedDuration {
                        Text("•").font(.caption2).foregroundStyle(.quaternary)
                        Text(dur).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Configuration Panel

private struct CompressConfigPanel: View {
    @Environment(CompressViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                selectedFileHeader
                encoderSection
                qualitySection
                contentTypeSection
                if viewModel.contentType == .anime {
                    animeSettingsSection
                }
                outputDirectorySection
                startSection
            }
            .padding(20)
        }
        .background(.background)
    }

    // MARK: - Selected File Header

    @ViewBuilder
    private var selectedFileHeader: some View {
        if let file = viewModel.selectedFile {
            GroupBox {
                HStack(spacing: 10) {
                    Image(systemName: "film")
                        .font(.title2)
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.fileName)
                            .font(.headline)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            Text(file.fileExtension.uppercased())
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.orange.opacity(0.12))
                                .foregroundStyle(.orange)
                                .clipShape(RoundedRectangle(cornerRadius: 3))

                            Text(file.formattedFileSize)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let res = file.resolutionString {
                                Text("•").foregroundStyle(.quaternary)
                                Text(res).font(.caption).foregroundStyle(.secondary)
                            }
                            if let dur = file.formattedDuration {
                                Text("•").foregroundStyle(.quaternary)
                                Text(dur).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer()
                }
                .padding(2)
            }
        }

        HStack {
            Image(systemName: "text.badge.checkmark")
                .foregroundStyle(.secondary)
            Text(viewModel.batchSummary)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Encoder Section

    @ViewBuilder
    private var encoderSection: some View {
        @Bindable var viewModel = viewModel
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Encoder Engine", systemImage: "gearshape.2")
                    .font(.headline)

                Picker("Encoder", selection: $viewModel.encoder) {
                    ForEach(CompressEncoder.allCases) { enc in
                        Label(enc.displayName, systemImage: enc.symbolName)
                            .tag(enc)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.encoder) {
                    viewModel.onEncoderChanged()
                }

                Text(viewModel.encoder.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(4)
        }
    }

    // MARK: - Quality Section

    @ViewBuilder
    private var qualitySection: some View {
        @Bindable var viewModel = viewModel
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Quality", systemImage: "slider.horizontal.3")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(viewModel.encoder.qualityLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(viewModel.quality)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }

                    Slider(
                        value: Binding(
                            get: { Double(viewModel.quality) },
                            set: { viewModel.updateQuality(Int($0)) }
                        ),
                        in: 0...Double(viewModel.encoder.maxQuality),
                        step: 1
                    )

                    Text("Default visually lossless: \(viewModel.encoder.defaultQuality)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(4)
        }
    }

    // MARK: - Content Type Section

    @ViewBuilder
    private var contentTypeSection: some View {
        @Bindable var viewModel = viewModel
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Content Type", systemImage: "sparkles.rectangle.stack")
                    .font(.headline)

                Picker("Content", selection: $viewModel.contentType) {
                    ForEach(ContentType.allCases) { type in
                        Label(type.displayName, systemImage: type.symbolName)
                            .tag(type)
                    }
                }
                .pickerStyle(.segmented)

                Text(viewModel.contentType.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(4)
        }
    }

    // MARK: - Anime Settings Section

    @ViewBuilder
    private var animeSettingsSection: some View {
        @Bindable var viewModel = viewModel
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Anime Tuning", systemImage: "sparkles.tv")
                    .font(.headline)

                // B-Frames
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("B-Frames")
                            .font(.body)
                        Spacer()
                        Text("\(viewModel.bFrames)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }

                    Slider(
                        value: Binding(
                            get: { Double(viewModel.bFrames) },
                            set: { viewModel.bFrames = Int($0) }
                        ),
                        in: 0...7,
                        step: 1
                    )

                    Text("More B-Frames = better compression for animation. 0 = disabled.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Divider()

                // Long GOP
                Toggle(isOn: $viewModel.longGOPEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Long GOP (10 seconds)")
                            .font(.body)
                        Text("GOP of 240 frames. Better compression, slower seeking.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
            .padding(4)
        }
    }

    // MARK: - Output Directory Section

    private var outputDirectorySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Output Directory", systemImage: "folder")
                    .font(.headline)

                HStack(spacing: 8) {
                    if let url = viewModel.outputDirectoryURL {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.orange)
                        Text(url.path)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .help(url.path)
                        Spacer()
                        Button("Change") {
                            viewModel.selectOutputDirectory()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Image(systemName: "folder.badge.questionmark")
                            .foregroundStyle(.secondary)
                        Text("Choose where compressed files will be saved")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Choose…") {
                            viewModel.selectOutputDirectory()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                Text("Output files are named <input>_compressed.<ext>.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(4)
        }
    }

    // MARK: - Start Section

    private var startSection: some View {
        HStack {
            Spacer()
            VStack(spacing: 4) {
                Button {
                    viewModel.startProcessing()
                } label: {
                    Label("Start Compression", systemImage: "play.fill")
                        .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.large)
                .disabled(!viewModel.canStartProcessing)

                Text("\(viewModel.files.count) file\(viewModel.files.count == 1 ? "" : "s") queued")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.top, 8)
    }
}

// MARK: - Processing View

private struct CompressProcessingView: View {
    @Environment(CompressViewModel.self) private var viewModel
    @State private var selectedJobID: UUID?
    @State private var showLog: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            processingHeader
            Divider()
            jobList
            Divider()
            if showLog, let job = selectedJob {
                logPanel(job: job)
                Divider()
            }
            processingFooter
        }
        .background(.background)
        .onAppear {
            selectedJobID = viewModel.jobs.first?.id
        }
    }

    private var processingHeader: some View {
        VStack(spacing: 8) {
            HStack {
                if viewModel.isProcessing {
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

                Text("\(viewModel.currentJobIndex)/\(viewModel.totalJobs)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }

            ProgressView(value: viewModel.overallProgress, total: 1.0)
                .progressViewStyle(.linear)
                .tint(viewModel.allJobsFinished ? .green : .orange)

            HStack(spacing: 16) {
                configBadge(icon: viewModel.encoder.symbolName, text: viewModel.encoder.displayName)
                configBadge(icon: "slider.horizontal.3", text: "\(viewModel.quality)")
                configBadge(icon: viewModel.contentType.symbolName, text: viewModel.contentType.displayName)
                Spacer()
            }
        }
        .padding(16)
    }

    private var headerTitle: String {
        if viewModel.allJobsFinished {
            let failed = viewModel.failedJobCount
            return failed > 0 ? "Completed with \(failed) error\(failed == 1 ? "" : "s")" : "All Compressions Completed"
        }
        return "Compressing..."
    }

    private func configBadge(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .foregroundStyle(.secondary)
    }

    private var jobList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(viewModel.jobs) { job in
                    CompressJobRow(job: job)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedJobID == job.id ? Color.orange.opacity(0.06) : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { selectedJobID = job.id }
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxHeight: .infinity)
    }

    private func logPanel(job: CompressJob) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Log Output", systemImage: "terminal")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { job.logLines.removeAll() } label: {
                    Image(systemName: "trash").font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
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

    private var processingFooter: some View {
        HStack(spacing: 12) {
            Button {
                showLog.toggle()
            } label: {
                Label(showLog ? "Hide Log" : "Show Log", systemImage: "terminal")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

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

            if viewModel.isProcessing {
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

    private var selectedJob: CompressJob? {
        guard let id = selectedJobID else { return viewModel.jobs.first }
        return viewModel.jobs.first(where: { $0.id == id })
    }
}

// MARK: - Compress Job Row

private struct CompressJobRow: View {
    var job: CompressJob

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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

                if job.hdrMode == .hdr10 {
                    Text("HDR")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.purple.opacity(0.15))
                        .foregroundStyle(.purple)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                Spacer()
                stateLabel
            }

            if job.state == .running || job.state == .completed {
                ProgressView(value: job.progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(job.state == .completed ? .green : .orange)

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

    @ViewBuilder
    private var stateLabel: some View {
        switch job.state {
        case .idle:
            Text("Ready").font(.caption).foregroundStyle(.secondary)
        case .queued:
            Text("Queued").font(.caption).foregroundStyle(.orange)
        case .running:
            Text("\(Int(job.progress * 100))%")
                .font(.caption).fontWeight(.semibold).monospacedDigit().foregroundStyle(.orange)
        case .completed:
            Text("Done").font(.caption).fontWeight(.semibold).foregroundStyle(.green)
        case .failed:
            Text("Failed").font(.caption).fontWeight(.semibold).foregroundStyle(.red)
        case .cancelled:
            Text("Cancelled").font(.caption).fontWeight(.semibold).foregroundStyle(.yellow)
        }
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(.caption2))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(.caption, design: .monospaced, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}
