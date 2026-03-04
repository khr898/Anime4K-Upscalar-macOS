// Anime4K-Upscaler/Views/ContentView.swift
// Root TabView with three feature tabs: Upscale, Compress, Stream Optimize.

import SwiftUI

struct ContentView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        TabView {
            UpscaleView()
                .tabItem {
                    Label("Upscale", systemImage: "wand.and.stars")
                }

            CompressView()
                .tabItem {
                    Label("Compress", systemImage: "archivebox")
                }

            StreamOptimizeView()
                .tabItem {
                    Label("Stream Optimize", systemImage: "bolt.badge.film")
                }
        }
    }
}

