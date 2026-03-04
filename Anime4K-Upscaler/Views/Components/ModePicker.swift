// Anime4K-Upscaler/Views/Components/ModePicker.swift
// Sectioned picker for all 15 Anime4K processing modes.

import SwiftUI

struct ModePicker: View {
    @Binding var selectedMode: Anime4KMode

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ModeCategory.allCases) { category in
                Section {
                    ForEach(category.modes) { mode in
                        ModeRow(mode: mode, isSelected: selectedMode == mode)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedMode = mode
                            }
                    }
                } header: {
                    HStack(spacing: 6) {
                        Image(systemName: category.symbolName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(category.rawValue)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, category == .hq ? 4 : 12)
                    .padding(.bottom, 4)
                }
            }
        }
    }
}

// MARK: - Mode Row

struct ModeRow: View {
    let mode: Anime4KMode
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Selection indicator
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.body)
                .foregroundStyle(isSelected ? Color.blue : Color.secondary.opacity(0.6))
                .frame(width: 20)

            // Mode number badge
            Text("\(mode.rawValue)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.blue : Color.secondary.opacity(0.5))
                )

            // Mode info
            VStack(alignment: .leading, spacing: 1) {
                Text(mode.displayName)
                    .font(.system(.body, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)

                Text(mode.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.blue.opacity(0.08) : Color.clear)
        )
    }
}
