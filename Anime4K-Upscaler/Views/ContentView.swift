// Anime4K-Upscaler/Views/ContentView.swift
// Root TabView with three feature tabs: Upscale, Compress, Stream Optimize.

import SwiftUI

struct ContentView: View {
    @Environment(AppViewModel.self) private var viewModel
    @SceneStorage("a4k.mainTab") private var selectedMainTabRaw: String = AppViewModel.MainTab.upscale.rawValue

    private var selectedMainTab: Binding<AppViewModel.MainTab> {
        Binding(
            get: {
                AppViewModel.MainTab(rawValue: selectedMainTabRaw) ?? .upscale
            },
            set: { newValue in
                selectedMainTabRaw = newValue.rawValue
                viewModel.selectedMainTab = newValue
            }
        )
    }

    var body: some View {
        TabView(selection: selectedMainTab) {
            UpscaleView()
                .tag(AppViewModel.MainTab.upscale)
                .tabItem {
                    Label("Upscale", systemImage: "wand.and.stars")
                }

            CompressView()
                .tag(AppViewModel.MainTab.compress)
                .tabItem {
                    Label("Compress", systemImage: "archivebox")
                }

            StreamOptimizeView()
                .tag(AppViewModel.MainTab.streamOptimize)
                .tabItem {
                    Label("Stream Optimize", systemImage: "bolt.badge.film")
                }

            QualityTuneView()
                .tag(AppViewModel.MainTab.qualityTune)
                .tabItem {
                    Label("Quality Tune", systemImage: "dial.medium")
                }
        }
        .onAppear {
            if let saved = AppViewModel.MainTab(rawValue: selectedMainTabRaw) {
                viewModel.selectedMainTab = saved
            }
        }
    }
}

private struct QualityTuneView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Quality Tune", systemImage: "dial.medium")
                            .font(.headline)

                        Text("Runs short sample encodes and compares SSIM/PSNR, then recommends the best Q/CRF using the same metric style as the benchmark tooling.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(4)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Input Video", systemImage: "film")
                            .font(.headline)

                        HStack {
                            if let input = vm.qualityTuneInputURL {
                                Text(input.path)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("No file selected")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }

                            Spacer()

                            Button("Choose…") {
                                vm.selectQualityTuneInputFile()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(4)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Scan Settings", systemImage: "slider.horizontal.3")
                            .font(.headline)

                        Picker("Codec", selection: $vm.qualityTuneCodec) {
                            ForEach(VideoCodec.allCases) { codec in
                                Text(codec.displayName).tag(codec)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: vm.qualityTuneCodec) {
                            vm.onQualityTuneCodecChanged()
                        }

                        HStack(spacing: 10) {
                            Stepper("\(vm.qualityTuneValueLabel) Start: \(vm.qualityTuneRangeStart)", value: $vm.qualityTuneRangeStart, in: 0...100)
                            Stepper("\(vm.qualityTuneValueLabel) End: \(vm.qualityTuneRangeEnd)", value: $vm.qualityTuneRangeEnd, in: 0...100)
                            Stepper("Step: \(vm.qualityTuneStep)", value: $vm.qualityTuneStep, in: 1...10)
                        }

                        HStack(spacing: 10) {
                            Stepper("Sample seconds: \(vm.qualityTuneSampleSeconds)", value: $vm.qualityTuneSampleSeconds, in: 5...120)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Target SSIM: \(String(format: "%.4f", vm.qualityTuneTargetSSIM))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Slider(value: $vm.qualityTuneTargetSSIM, in: 0.95...1.0, step: 0.001)
                            }
                        }
                    }
                    .padding(4)
                }

                HStack(spacing: 10) {
                    Button {
                        vm.runQualityTuneScan()
                    } label: {
                        if vm.qualityTuneIsRunning {
                            Label("Scanning...", systemImage: "hourglass")
                        } else {
                            Label("Run Scan", systemImage: "play.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.qualityTuneIsRunning || vm.qualityTuneInputURL == nil)

                    if !vm.qualityTuneStatusText.isEmpty {
                        Text(vm.qualityTuneStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = vm.qualityTuneErrorText {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let best = vm.qualityTuneBestCandidate {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Recommended", systemImage: "checkmark.seal.fill")
                                .font(.headline)
                                .foregroundStyle(.green)
                            Text("\(best.valueLabel) • SSIM \(String(format: "%.4f", best.ssim)) • PSNR \(String(format: "%.2f", best.psnr)) dB • \(best.sizeLabel)")
                                .font(.callout)
                        }
                        .padding(4)
                    }
                }

                if !vm.qualityTuneCandidates.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Candidates", systemImage: "list.bullet")
                                .font(.headline)

                            ForEach(vm.qualityTuneCandidates) { candidate in
                                HStack {
                                    Text(candidate.valueLabel)
                                        .font(.caption)
                                        .frame(width: 80, alignment: .leading)
                                    Text("SSIM \(String(format: "%.4f", candidate.ssim))")
                                        .font(.caption)
                                        .frame(width: 100, alignment: .leading)
                                    Text("PSNR \(String(format: "%.2f", candidate.psnr)) dB")
                                        .font(.caption)
                                        .frame(width: 130, alignment: .leading)
                                    Text(candidate.sizeLabel)
                                        .font(.caption)
                                    Spacer()
                                }
                            }
                        }
                        .padding(4)
                    }
                }
            }
            .padding(20)
        }
    }
}

