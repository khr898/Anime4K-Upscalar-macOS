// Anime4K-Upscaler/Views/Detail/ConfigurationPanel.swift
// Main configuration interface: mode, resolution, codec, compression, GOP.

import SwiftUI

struct ConfigurationPanel: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Selected file header
                selectedFileHeader

                // Mode selection
                modeSection

                // Resolution
                resolutionSection

                // Codec
                codecSection

                // Compression
                compressionSection

                // Advanced
                advancedSection

                // Output directory
                outputDirectorySection

                // Start button
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
                        .foregroundStyle(.blue)

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
                                .background(.blue.opacity(0.12))
                                .foregroundStyle(.blue)
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

        // Batch summary
        HStack {
            Image(systemName: "text.badge.checkmark")
                .foregroundStyle(.secondary)
            Text(viewModel.batchSummary)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Mode Section

    @ViewBuilder
    private var modeSection: some View {
        @Bindable var viewModel = viewModel
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Anime4K Mode", systemImage: "wand.and.stars")
                    .font(.headline)

                ScrollView {
                    ModePicker(selectedMode: $viewModel.configuration.mode)
                }
                .frame(maxHeight: 320)
            }
            .padding(4)
        }
    }

    // MARK: - Resolution Section

    @ViewBuilder
    private var resolutionSection: some View {
        @Bindable var viewModel = viewModel
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Target Resolution", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.headline)

                Picker("Resolution", selection: $viewModel.configuration.resolution) {
                    ForEach(TargetResolution.allCases) { res in
                        Text(res.displayName)
                            .tag(res)
                    }
                }
                .pickerStyle(.segmented)

                // Subtitle for selected resolution
                Text(viewModel.configuration.resolution.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(4)
        }
    }

    // MARK: - Codec Section

    @ViewBuilder
    private var codecSection: some View {
        @Bindable var viewModel = viewModel
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Video Codec", systemImage: "film.stack")
                    .font(.headline)

                Picker("Codec", selection: $viewModel.configuration.codec) {
                    ForEach(VideoCodec.allCases) { codec in
                        Label(codec.displayName, systemImage: codec.symbolName)
                            .tag(codec)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.configuration.codec) {
                    viewModel.onCodecChanged()
                }

                // Subtitle for selected codec
                Text(viewModel.configuration.codec.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(4)
        }
    }

    // MARK: - Compression Section

    @ViewBuilder
    private var compressionSection: some View {
        @Bindable var viewModel = viewModel
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Compression", systemImage: "archivebox")
                    .font(.headline)

                Picker("Compression", selection: $viewModel.compressionPreset) {
                    ForEach(CompressionPreset.allCases) { preset in
                        HStack {
                            Image(systemName: preset.symbolName)
                            Text(preset.displayName)
                        }
                        .tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: viewModel.compressionPreset) {
                    viewModel.syncCompression()
                }

                // Custom Quality Slider
                if viewModel.compressionPreset == .customQuality {
                    let isAV1 = viewModel.configuration.codec.usesCRF
                    let maxVal = isAV1 ? 63 : 100
                    let labelText = isAV1 ? "CRF" : "Quality"

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(labelText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(viewModel.customQualityValue)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }

                        Slider(
                            value: Binding(
                                get: { Double(viewModel.customQualityValue) },
                                set: { viewModel.updateCustomQuality(Int($0)) }
                            ),
                            in: 0...Double(maxVal),
                            step: 1
                        )
                    }
                }

                // Custom Bitrate Stepper
                if viewModel.compressionPreset == .fixedBitrate {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Bitrate (Mbps)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(viewModel.customBitrateValue) Mbps")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }

                        HStack(spacing: 8) {
                            Slider(
                                value: Binding(
                                    get: { Double(viewModel.customBitrateValue) },
                                    set: { viewModel.updateCustomBitrate(Int($0)) }
                                ),
                                in: 1...200,
                                step: 1
                            )

                            Stepper(
                                "",
                                value: Binding(
                                    get: { viewModel.customBitrateValue },
                                    set: { viewModel.updateCustomBitrate($0) }
                                ),
                                in: 1...200
                            )
                            .labelsHidden()
                        }
                    }
                }

                // Compression summary
                Text(viewModel.configuration.compression.subtitle(for: viewModel.configuration.codec))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(4)
        }
    }

    // MARK: - Advanced Section

    @ViewBuilder
    private var advancedSection: some View {
        @Bindable var viewModel = viewModel
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Advanced", systemImage: "gearshape")
                    .font(.headline)

                Toggle(isOn: $viewModel.configuration.longGOPEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Long GOP (10 seconds)")
                            .font(.body)
                        Text("Saves ~10-15% space. Seeking may be slightly slower.")
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
                            .foregroundStyle(.blue)
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
                        Text("Choose where processed files will be saved")
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

                Text("Required for sandboxed file access. Output files are named <input>_Mode<N>_<scale>x.<ext>.")
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
                    Label("Start Processing", systemImage: "play.fill")
                        .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
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
