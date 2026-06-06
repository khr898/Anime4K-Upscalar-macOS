// Anime4K-Upscaler/Views/Detail/EmptyStateView.swift
// Placeholder view when no files are loaded.

import SwiftUI

struct EmptyStateView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "wand.and.stars")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
                .symbolEffect(.pulse, options: .repeating.speed(0.3))

            Text("Anime4K Upscaler")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            Text("Add video files to get started")
                .font(.body)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button {
                    viewModel.addFiles()
                } label: {
                    Label("Add Files", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                featureRow(symbol: "film.stack", text: "Drag & drop or browse for video files")
                featureRow(symbol: "sparkles", text: "15 Anime4K shader modes (HQ, Fast, No-Upscale)")
                featureRow(symbol: "arrow.up.left.and.arrow.down.right", text: "2x or 4x upscaling with GPU acceleration")
                featureRow(symbol: "bolt.fill", text: "HEVC Hardware or AV1 Software encoding")
            }
            .padding(.top, 8)
            .padding(.horizontal, 40)

            Spacer()

            // Supported formats
            HStack(spacing: 4) {
                Text("Supported:")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                ForEach(SupportedVideoExtension.allCases, id: \.rawValue) { ext in
                    Text(ext.rawValue.uppercased())
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.quaternary.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private func featureRow(symbol: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(.blue)
                .frame(width: 18)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
