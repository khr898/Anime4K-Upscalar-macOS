// Anime4K-Upscaler/Views/StreamOptimize/StreamOptimizeView.swift
// Complete Stream Optimize feature UI — configurable encoding, directory selection, file list, processing.

import SwiftUI
import UniformTypeIdentifiers

struct StreamOptimizeView: View {
    @Environment(StreamOptimizeViewModel.self) private var viewModel

    var body: some View {
        NavigationSplitView {
            BatchQueueSidebar<StreamOptimizeBatch>(
                items: viewModel.batches,
                selection: viewModel.selectedBatchID,
                onSelect: { viewModel.selectedBatchID = $0 },
                onCancel: { viewModel.cancelBatch(id: $0) },
                onDelete: { viewModel.deleteBatch(id: $0) },
                onNewBatch: { viewModel.returnToConfiguration() },
                onStartQueue: { viewModel.startProcessing() },
                summary: { batch in
                    "\(batch.configuration.encoder.displayName) · \(batch.configuration.profile.displayName)"
                }
            )
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            switch viewModel.viewState {
            case .configuration:
                stagingView
            case .processing:
                StreamOptimizeProcessingView()
            }
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                streamToolbarButtons
            }
        }
    }

    /// Staging detail: preset controls + staging file list + "Add to Queue".
    @ViewBuilder
    private var stagingView: some View {
        if viewModel.files.isEmpty && viewModel.batches.isEmpty {
            StreamOptimizeEmptyStateView()
        } else {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        StreamOptimizeConfigView()
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
                StreamOptimizeFileListView()
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

    @ViewBuilder
    private var streamToolbarButtons: some View {
        if viewModel.viewState == .configuration {
            Button {
                viewModel.addFiles()
            } label: {
                Label("Add Files", systemImage: "plus")
            }
            .help("Add video files or folders to staging")

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
                    Label("Optimize", systemImage: "play.fill")
                }
                .help("Start processing the queue")
                .disabled(!viewModel.canStartProcessing)
            }
        } else {
            if viewModel.canStartProcessing {
                Button {
                    viewModel.startProcessing()
                } label: {
                    Label("Optimize", systemImage: "play.fill")
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

// MARK: - Configuration View

private struct StreamOptimizeConfigView: View {
    @Environment(StreamOptimizeViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Selected File Header & Staging count
                selectedFileHeader

                // Encoding Settings
                encoderSection

                // SVT-AV1 Preset (when AV1 is chosen)
                if viewModel.encoder == .svtAV1 {
                    svtPresetSection
                }

                // Quality
                qualitySection

                // Profile & Pixel Format
                profilePixelFormatSection

                // Audio
                audioSection

                // Subtitles
                subtitleSection

                // Streaming & Keyframe
                streamingSection

                // Output Directory
                outputDirectorySection

                // Start Button
                startSection
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        .foregroundStyle(.teal)

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
                                .background(.teal.opacity(0.12))
                                .foregroundStyle(.teal)
                                .clipShape(RoundedRectangle(cornerRadius: 3))

                            Text(file.formattedFileSize)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let res = file.resolutionString {
                                Text("•")
                                    .foregroundStyle(.quaternary)
                                Text(res)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let dur = file.formattedDuration {
                                Text("•")
                                    .foregroundStyle(.quaternary)
                                Text(dur)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer()
                }
                .padding(2)
            }
        }

        if viewModel.files.count > 1 {
            HStack {
                Image(systemName: "square.stack.3d.up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(viewModel.files.count) files staged for batch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Encoder Section

    private var encoderSection: some View {
        @Bindable var vm = viewModel
        return GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("Video Encoder", systemImage: "video")
                    .font(.headline)

                Picker("Encoder", selection: $vm.encoder) {
                    ForEach(StreamEncoder.allCases) { enc in
                        Text(enc.displayName).tag(enc)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                HStack(spacing: 6) {
                    Image(systemName: viewModel.encoder.symbolName)
                        .font(.caption)
                        .foregroundStyle(.teal)
                    Text(viewModel.encoder.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(4)
        }
    }

    // MARK: - SVT-AV1 Preset Section

    private var svtPresetSection: some View {
        @Bindable var vm = viewModel
        return GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("AV1 Speed Preset", systemImage: "gauge.with.dots.needle.67percent")
                    .font(.headline)

                HStack {
                    Slider(
                        value: Binding(
                            get: { Double(viewModel.svtAV1Preset) },
                            set: { viewModel.svtAV1Preset = Int($0) }
                        ),
                        in: 0...13,
                        step: 1
                    )

                    Text("\(viewModel.svtAV1Preset)")
                        .font(.body)
                        .fontWeight(.semibold)
                        .frame(width: 24, alignment: .trailing)
                        .monospacedDigit()
                }

                Text(svtPresetDescription(viewModel.svtAV1Preset))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(4)
        }
    }

    private func svtPresetDescription(_ preset: Int) -> String {
        switch preset {
        case 0...3:
            return "Archival (Slowest, Maximum Compression)"
        case 4...6:
            return "Standard (Balanced Speed & Quality - Recommended)"
        case 7...10:
            return "Fast (High Speed, Moderate Compression)"
        case 11...13:
            return "Real-time (Ultra Fast, Lower Compression)"
        default:
            return ""
        }
    }

    // MARK: - Quality Section

    private var qualitySection: some View {
        @Bindable var vm = viewModel
        return GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(viewModel.encoder.qualityLabel, systemImage: "slider.horizontal.3")
                        .font(.headline)
                    Spacer()
                    Text("\(viewModel.quality)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }

                Slider(
                    value: Binding(
                        get: { Double(viewModel.quality) },
                        set: { viewModel.quality = Int($0) }
                    ),
                    in: 0...Double(viewModel.encoder.maxQuality),
                    step: 1
                )

                if viewModel.encoder.usesCRF {
                    Text("Lower CRF = higher quality, larger file. 28 is recommended for streaming.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Higher value = better quality, larger file. 65 is recommended for streaming.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(4)
        }
    }

    // MARK: - Profile & Pixel Format Section

    private var profilePixelFormatSection: some View {
        @Bindable var vm = viewModel
        return GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Profile & Pixel Format", systemImage: "film")
                    .font(.headline)

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Profile")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Profile", selection: $vm.profile) {
                            ForEach(viewModel.encoder.availableProfiles) { prof in
                                Text(prof.displayName).tag(prof)
                            }
                        }
                        .labelsHidden()
                        .frame(minWidth: 130)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pixel Format")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Pixel Format", selection: $vm.pixelFormat) {
                            ForEach(viewModel.encoder.availablePixelFormats) { fmt in
                                Text(fmt.displayName).tag(fmt)
                            }
                        }
                        .labelsHidden()
                        .frame(minWidth: 160)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(viewModel.profile.subtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(4)
        }
    }

    // MARK: - Audio Section

    private var audioSection: some View {
        @Bindable var vm = viewModel
        return GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Audio", systemImage: "speaker.wave.2")
                    .font(.headline)

                Picker("Audio Mode", selection: $vm.audioMode) {
                    ForEach(StreamAudioMode.allCases) { mode in
                        Label(mode.displayName, systemImage: mode.symbolName).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                Text(viewModel.audioMode.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(4)
        }
    }

    // MARK: - Subtitle Section

    private var subtitleSection: some View {
        @Bindable var vm = viewModel
        return GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Subtitles", systemImage: "text.bubble")
                    .font(.headline)

                Picker("Subtitle Mode", selection: $vm.subtitleMode) {
                    ForEach(StreamSubtitleMode.allCases) { mode in
                        Label(mode.displayName, systemImage: mode.symbolName).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                Text(viewModel.subtitleMode.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(4)
        }
    }

    // MARK: - Streaming / Keyframe Section

    private var streamingSection: some View {
        @Bindable var vm = viewModel
        return GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Streaming & Seeking", systemImage: "forward.frame")
                    .font(.headline)

                // Keyframe Interval
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Keyframe Interval")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text(viewModel.keyframeInterval.displayName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.teal)
                    }

                    Picker("Keyframe Interval", selection: $vm.keyframeInterval) {
                        ForEach(KeyframeInterval.allCases) { interval in
                            Text(interval.displayName).tag(interval)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.caption2)
                            .foregroundStyle(.teal)
                        Text(viewModel.keyframeInterval.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("Shorter intervals enable faster seeking but increase file size slightly. 2 seconds is ideal for streaming.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Divider()

                // Faststart & SW Fallback
                HStack(spacing: 24) {
                    Toggle(isOn: $vm.faststart) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Faststart")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Move moov atom to file start for instant playback")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(.teal)

                    if viewModel.encoder != .svtAV1 {
                        Toggle(isOn: $vm.allowSWFallback) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("SW Fallback")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("Allow software encoding if hardware is unavailable")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .toggleStyle(.switch)
                        .tint(.teal)
                    }
                }
            }
            .padding(4)
        }
    }

    // MARK: - Output Directory Section

    private var outputDirectorySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Output Directory", systemImage: "folder.fill.badge.plus")
                    .font(.headline)

                HStack(spacing: 8) {
                    if let url = viewModel.destinationDirectoryURL {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.teal)
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
                        Text("Default (Same as input file)")
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

                Text("Output files are named <input>_streaming.mp4.")
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
                    Label("Start Optimization", systemImage: "play.fill")
                        .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .controlSize(.large)
                .disabled(!viewModel.canStartProcessing)

                if viewModel.files.isEmpty && viewModel.batches.isEmpty {
                    Text("Add files to optimize")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else if !viewModel.files.isEmpty {
                    Text("\(viewModel.files.count) file\(viewModel.files.count == 1 ? "" : "s") staged")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    let pendingCount = viewModel.batches.filter { $0.state == .pending }.count
                    Text("\(pendingCount) batch\(pendingCount == 1 ? "" : "es") queued")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(.top, 8)
    }
}

// MARK: - Processing View

private struct StreamOptimizeProcessingView: View {
    @Environment(StreamOptimizeViewModel.self) private var viewModel
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

    /// Get configuration from the first job for badge display.
    private var activeConfig: StreamOptimizeConfiguration? {
        viewModel.jobs.first?.configuration
    }

    private var processingHeader: some View {
        VStack(spacing: 8) {
            HStack {
                if viewModel.isQueueProcessing {
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
                .tint(viewModel.allJobsFinished ? .green : .teal)

            if let config = activeConfig {
                HStack(spacing: 10) {
                    configBadge(icon: config.encoder.symbolName, text: config.encoder.displayName)
                    if config.encoder.usesCRF {
                        configBadge(icon: "slider.horizontal.3", text: "CRF:\(config.quality)")
                    } else {
                        configBadge(icon: "slider.horizontal.3", text: "Q:\(config.quality)")
                    }
                    configBadge(icon: "forward.frame", text: "KF:\(config.keyframeInterval.displayName)")
                    if config.faststart {
                        configBadge(icon: "bolt.badge.film", text: "Faststart")
                    }
                    if !config.audioMode.isCopy {
                        configBadge(icon: "waveform", text: config.audioMode.displayName)
                    }
                    Spacer()
                }
            }
        }
        .padding(16)
    }

    private var headerTitle: String {
        if viewModel.allJobsFinished {
            let failed = viewModel.failedJobCount
            return failed > 0 ? "Completed with \(failed) error\(failed == 1 ? "" : "s")" : "All Optimizations Completed"
        }
        return "Optimizing for Streaming..."
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
                    StreamOptimizeJobRow(job: job)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedJobID == job.id ? Color.teal.opacity(0.06) : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { selectedJobID = job.id }
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxHeight: .infinity)
    }

    private func logPanel(job: StreamOptimizeJob) -> some View {
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

            if viewModel.canStartProcessing && !viewModel.isQueueProcessing && !viewModel.allJobsFinished {
                Button {
                    viewModel.startProcessing()
                } label: {
                    Label("Start Optimization", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .controlSize(.small)
            } else if viewModel.isQueueProcessing {
                Button {
                    viewModel.cancelAllQueued()
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

    private var selectedJob: StreamOptimizeJob? {
        guard let id = selectedJobID else { return viewModel.jobs.first }
        return viewModel.jobs.first(where: { $0.id == id })
    }
}

// MARK: - Stream Optimize Job Row

private struct StreamOptimizeJobRow: View {
    var job: StreamOptimizeJob

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

                Spacer()
                stateLabel
            }

            if job.state == .running || job.state == .completed {
                ProgressView(value: job.progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(job.state == .completed ? .green : .teal)

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
                .font(.caption).fontWeight(.semibold).monospacedDigit().foregroundStyle(.teal)
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

// MARK: - File List Sidebar

private struct StreamOptimizeFileListView: View {
    @Environment(StreamOptimizeViewModel.self) private var viewModel
    @State private var isDropTargeted: Bool = false

    var body: some View {
        @Bindable var viewModel = viewModel
        VStack(spacing: 0) {
            header
            Divider()
            if viewModel.files.isEmpty {
                placeholder
            } else {
                fileList
            }
            Divider()
            footer
        }
        .background(.regularMaterial)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private var header: some View {
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

    private var placeholder: some View {
        Button {
            viewModel.addFiles()
        } label: {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)
                Text("Drop Video Files Here")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("or click to browse")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.teal.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .padding(8)
            }
        }
    }

    @ViewBuilder
    private var fileList: some View {
        @Bindable var viewModel = viewModel
        List(selection: $viewModel.selectedFileID) {
            ForEach(viewModel.files) { file in
                StreamOptimizeFileRow(file: file)
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
                    .fill(.teal.opacity(0.08))
                    .strokeBorder(.teal.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .padding(4)
            }
        }
    }

    private var footer: some View {
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

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var didAdd = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil, isAbsolute: true) else { return }
                    Task { @MainActor in viewModel.addFilesFromDrop([url]) }
                }
                didAdd = true
            }
        }
        return didAdd
    }
}

private struct StreamOptimizeFileRow: View {
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
                        .background(.teal.opacity(0.12))
                        .foregroundStyle(.teal)
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

// MARK: - Empty State View

private struct StreamOptimizeEmptyStateView: View {
    @Environment(StreamOptimizeViewModel.self) private var viewModel
    @State private var isTargeted: Bool = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "bolt.badge.film")
                    .font(.system(size: 56))
                    .foregroundStyle(.teal)

                Text("Stream Optimize")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Transcode and optimize videos for ultra-fast streaming playback, frame-accurate seeking, and wide device compatibility.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }

            Button {
                viewModel.addFiles()
            } label: {
                Label("Add Files / Folders", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)
            .controlSize(.large)

            VStack(alignment: .leading, spacing: 8) {
                featureBullet(icon: "bolt.horizontal.fill", text: "Faststart (moov atom) at file beginning for instant playback")
                featureBullet(icon: "timer", text: "Enforced 2s keyframe intervals for seamless scrubbing")
                featureBullet(icon: "apple.logo", text: "Hardware-accelerated Apple Silicon HEVC VideoToolbox")
            }
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background {
            if isTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.teal.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .padding(16)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
    }

    private func featureBullet(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.teal)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var didAdd = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil, isAbsolute: true) else { return }
                    Task { @MainActor in viewModel.addFilesFromDrop([url]) }
                }
                didAdd = true
            }
        }
        return didAdd
    }
}
