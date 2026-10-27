//
//  SettingsView.swift
//  XClient
//
//  Native multiplatform preferences panel providing Appearance, Timeline Sync,
//  Media Storage management, and real-time interactive Live Sample Card preview.
//  100% Swift 6 strict concurrency compliance.
//

import SwiftUI
import XKitModels

/// Native settings surface presenting configurable application preferences.
@MainActor
public struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel
    @Environment(\.colorPalette) private var currentPalette
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @MainActor
    public init(viewModel: SettingsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    @MainActor
    public init() {
        _viewModel = StateObject(wrappedValue: SettingsViewModel())
    }

    public var body: some View {
        Form {
            // MARK: - Section 1: Appearance Customization
            Section {
                // Theme Mode Selector
                VStack(alignment: .leading, spacing: 12) {
                    Text("Theme Mode")
                        .font(.subheadline)
                        .foregroundStyle(currentPalette.textSecondary)

                    themePickerGrid
                }
                .padding(.vertical, 4)

                // Liquid Glass Intensity Slider
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Liquid Glass Intensity", systemImage: "sparkles")
                            .font(.body)
                        Spacer()
                        Text(viewModel.formattedGlassIntensityPercentage)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(currentPalette.accent)
                            .bold()
                    }

                    Slider(
                        value: $viewModel.glassIntensity,
                        in: 0.0...1.0,
                        step: 0.05
                    )
                    .tint(currentPalette.accent)

                    // Quick Preset Chips
                    HStack(spacing: 8) {
                        presetChip(title: "Off (0%)", value: 0.0)
                        presetChip(title: "Subtle (50%)", value: 0.5)
                        presetChip(title: "Vibrant (100%)", value: 1.0)
                    }

                    if reduceTransparency {
                        Label(
                            "System 'Reduce Transparency' is active. Opaque high-contrast fallback will be applied.",
                            systemImage: "accessibility"
                        )
                        .font(.caption)
                        .foregroundStyle(currentPalette.warning)
                        .padding(.top, 4)
                    }
                }
                .padding(.vertical, 6)

            } header: {
                Text("Appearance & Design")
            } footer: {
                Text("Configure high-contrast themes and Liquid Glass translucent material intensity.")
            }

            // MARK: - Section 2: Live Sample Card Preview
            Section {
                LiveSampleCardPreview(
                    preference: viewModel.selectedTheme,
                    glassIntensity: viewModel.glassIntensity
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                .listRowBackground(Color.clear)
            } header: {
                Text("Live Interactive Preview")
            } footer: {
                Text("Interact with the sample post card to observe real-time theme and material changes.")
            }

            // MARK: - Section 3: Timeline & Background Sync
            Section {
                Picker(selection: $viewModel.autoRefreshInterval) {
                    ForEach(PollingInterval.allCases) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                } label: {
                    Label("Auto-Refresh Feed", systemImage: "arrow.clockwise")
                }
                .pickerStyle(.menu)
            } header: {
                Text("Timeline & Sync")
            } footer: {
                Text("Background periodic polling automatically buffers new incoming posts in near real time.")
            }

            // MARK: - Section 4: Media & Storage Management
            Section {
                HStack {
                    Label("Media Disk Cache", systemImage: "internaldrive")
                    Spacer()
                    if viewModel.isCalculatingCache {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(viewModel.formattedCacheSize)
                            .foregroundStyle(currentPalette.textSecondary)
                    }

                    Button {
                        Task { await viewModel.calculateCacheSize() }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.isCalculatingCache)
                }

                Button(role: .destructive) {
                    viewModel.showPurgeConfirmation = true
                } label: {
                    HStack {
                        Label("Clear Media Cache", systemImage: "trash")
                        Spacer()
                        if viewModel.isPurgingCache {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(viewModel.isPurgingCache || viewModel.currentCacheSizeBytes == 0)

                if let status = viewModel.statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(currentPalette.textSecondary)
                }
            } header: {
                Text("Media & Storage")
            } footer: {
                Text("Removes locally cached media thumbnails and videos. Does not affect account data.")
            }

            // MARK: - Section 5: About & Diagnostics
            Section {
                LabeledContent("App Version", value: "1.0.0 (Build 2026.10)")
                LabeledContent("Target Platforms", value: "macOS 14+ / iOS 26+")
                LabeledContent("Concurrency Mode", value: "Swift 6 Strict (Complete)")
                LabeledContent("SDK Integration", value: "XKit Models, Transport, Auth, API")

                Button(role: .destructive) {
                    viewModel.showResetConfirmation = true
                } label: {
                    Label("Reset All Preferences to Defaults", systemImage: "arrow.counterclockwise")
                }
            } header: {
                Text("About XClient")
            }
        }
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await viewModel.calculateCacheSize()
        }
        .confirmationDialog(
            "Clear Media Cache?",
            isPresented: $viewModel.showPurgeConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Cache (\(viewModel.formattedCacheSize))", role: .destructive) {
                Task { await viewModel.purgeCache() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All locally cached preview images and videos will be purged from disk. They will be re-downloaded on demand.")
        }
        .confirmationDialog(
            "Reset All Preferences?",
            isPresented: $viewModel.showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset to Defaults", role: .destructive) {
                viewModel.resetToDefaults()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will restore Theme, Liquid Glass intensity, and Polling interval to default values.")
        }
    }

    // MARK: - Subviews

    private var themePickerGrid: some View {
        HStack(spacing: 8) {
            ForEach(AppThemePreference.allCases) { pref in
                let isSelected = (viewModel.selectedTheme == pref)
                Button {
                    viewModel.updateTheme(pref)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: pref.iconName)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(isSelected ? currentPalette.accent : currentPalette.textSecondary)

                        Text(pref.displayName)
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(isSelected ? currentPalette.textPrimary : currentPalette.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isSelected ? currentPalette.accent.opacity(0.12) : currentPalette.secondaryBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? currentPalette.accent : currentPalette.borderSubtle, lineWidth: isSelected ? 1.5 : 1.0)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func presetChip(title: String, value: Double) -> some View {
        Button {
            viewModel.updateGlassIntensity(value)
        } label: {
            Text(title)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(abs(viewModel.glassIntensity - value) < 0.05 ? currentPalette.accent.opacity(0.18) : currentPalette.secondaryBackground)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(abs(viewModel.glassIntensity - value) < 0.05 ? currentPalette.accent : currentPalette.borderSubtle, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
