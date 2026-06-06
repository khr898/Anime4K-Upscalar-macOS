// Anime4K-Upscaler/Views/StreamOptimize/StreamOptimizeView.swift
// Complete Stream Optimize feature UI — configurable encoding, directory selection, file list, processing.

import SwiftUI

struct StreamOptimizeView: View {
    @Environment(StreamOptimizeViewModel.self) private var viewModel

    var body: some View {
        Group {
            switch viewModel.viewState {
            case .configuration:
                StreamOptimizeConfigView()
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

    @ViewBuilder
    private var streamToolbarButtons: some View {
        if viewModel.viewState == .configuration {
            if viewModel.canStartProcessing {
                Button {
                    viewModel.startProcessing()
                } label: {
                    Label("Optimize", systemImage: "play.fill")
                }
                .help("Start stream optimization")
            }
        } else {
            if viewModel.isProcessing {
                Button {
                    viewModel.cancelProcessing()
                } label: {
                    Label("Cancel", systemImage: "stop.fill")
                }
                .help("Cancel optimization")
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

// MARK: - Configuration View

private struct StreamOptimizeConfigView: View {
    @Environment(StreamOptimizeViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Title
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("Stream Optimize", systemImage: "bolt.badge.film")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Spacer()
                        Button {
                            viewModel.resetToDefaults()
                        } label: {
                            Label("Reset Defaults", systemImage: "arrow.counterclockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Reset all settings to streaming-optimized defaults")
                    }

                    Text("Transcode videos for streaming delivery — optimized for quick seeking and broad compatibility")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                // Encoding Settings
                encoderSection

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

                // Source Directory
                sourceSection

                // Destination Directory
                destinationSection

                // File List
                if !viewModel.files.isEmpty {
                    fileListSection
                }

                // Start Button
                startSection
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
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
                        .font(.system(.title3, design: .monospaced, weight: .semibold))
                        .foregroundStyle(.teal)
                }

                Slider(
                    value: Binding(
                        get: { Double(viewModel.quality) },
                        set: { viewModel.quality = Int($0) }
                    ),
                    in: 0...Double(viewModel.encoder.maxQuality),
                    step: 1
                ) {
                    EmptyView()
                } minimumValueLabel: {
                    Text("0").font(.caption2).foregroundStyle(.tertiary)
                } maximumValueLabel: {
                    Text("\(viewModel.encoder.maxQuality)").font(.caption2).foregroundStyle(.tertiary)
                }
                .tint(.teal)

                if viewModel.encoder.usesCRF {
                    Text("Lower CRF = higher quality, larger file. 28 is a good balance for streaming.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Higher value = better quality, larger file. 65 is recommended for streaming.")
                        .font(.caption)
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
                        .foregroundStyle(.teal)
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
            VStack(alignment: .leading, spacing: 10) {
                Label("Audio", systemImage: "speaker.wave.2")
                    .font(.headline)

                Picker("Audio Mode", selection: $vm.audioMode) {
                    ForEach(StreamAudioMode.allCases) { mode in
                        HStack {
                            Image(systemName: mode.symbolName)
                            Text(mode.displayName)
                        }
                        .tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)

                HStack(spacing: 6) {
                    Image(systemName: viewModel.audioMode.symbolName)
                        .font(.caption)
                        .foregroundStyle(.teal)
                    Text(viewModel.audioMode.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(4)
        }
    }

    // MARK: - Subtitle Section

    private var subtitleSection: some View {
        @Bindable var vm = viewModel
        return GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("Subtitles", systemImage: "text.bubble")
                    .font(.headline)

                Picker("Subtitle Mode", selection: $vm.subtitleMode) {
                    ForEach(StreamSubtitleMode.allCases) { mode in
                        HStack {
                            Image(systemName: mode.symbolName)
                            Text(mode.displayName)
                        }
                        .tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)

                HStack(spacing: 6) {
                    Image(systemName: viewModel.subtitleMode.symbolName)
                        .font(.caption)
                        .foregroundStyle(.teal)
                    Text(viewModel.subtitleMode.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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

    // MARK: - Source Section

    private var sourceSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Source Directory", systemImage: "folder")
                    .font(.headline)

                HStack(spacing: 8) {
                    if let url = viewModel.sourceDirectoryURL {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.teal)
                        Text(url.path)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .help(url.path)
                        Spacer()

                        Text("\(viewModel.files.count) videos")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.teal.opacity(0.12))
                            .foregroundStyle(.teal)
                            .clipShape(Capsule())

                        Button("Change") {
                            viewModel.selectSourceDirectory()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Image(systemName: "folder.badge.questionmark")
                            .foregroundStyle(.secondary)
                        Text("Select folder containing videos to optimize")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Choose…") {
                            viewModel.selectSourceDirectory()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                Text("Scans for .mkv, .mp4, .webm files in the selected folder.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(4)
        }
    }

    // MARK: - Destination Section

    private var destinationSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Destination Directory", systemImage: "folder.fill.badge.plus")
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
                            viewModel.selectDestinationDirectory()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Image(systemName: "folder.badge.questionmark")
                            .foregroundStyle(.secondary)
                        Text("Choose where optimized files will be saved")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Choose…") {
                            viewModel.selectDestinationDirectory()
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

    // MARK: - File List Section

    private var fileListSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Found Videos", systemImage: "film.stack")
                        .font(.headline)

                    Spacer()

                    if let dur = viewModel.totalDuration {
                        Text(dur)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.quaternary)
                    }
                    Text(viewModel.totalFileSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(viewModel.files) { file in
                            HStack(spacing: 8) {
                                Image(systemName: "film")
                                    .font(.caption)
                                    .foregroundStyle(.teal)
                                    .frame(width: 16)

                                Text(file.fileName)
                                    .font(.system(.callout))
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Spacer()

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

                                if let dur = file.formattedDuration {
                                    Text(dur)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 3)
                            .padding(.horizontal, 4)
                        }
                    }
                }
                .frame(maxHeight: 240)
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

                if viewModel.files.isEmpty {
                    Text("Select a source directory first")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else if viewModel.destinationDirectoryURL == nil {
                    Text("Select a destination directory")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("\(viewModel.files.count) file\(viewModel.files.count == 1 ? "" : "s") ready")
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
