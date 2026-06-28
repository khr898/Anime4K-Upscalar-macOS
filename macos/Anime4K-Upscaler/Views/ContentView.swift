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

        }
        .onAppear {
            if let saved = AppViewModel.MainTab(rawValue: selectedMainTabRaw) {
                viewModel.selectedMainTab = saved
            }
        }
    }
}


