import SwiftUI

/// Settings backed by the app's saved appearance and media-cache state.
@MainActor
public struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel
    @Environment(\.colorPalette) private var palette

    public init(viewModel: SettingsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public init() {
        _viewModel = StateObject(wrappedValue: SettingsViewModel())
    }

    public var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $viewModel.selectedTheme) {
                    ForEach(AppThemePreference.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
            }

            Section {
                HStack {
                    Text("Downloaded media cache")
                    Spacer()
                    if viewModel.isCalculatingCache {
                        ProgressView()
                    } else {
                        Text(viewModel.formattedCacheSize)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                Button("Clear media cache", role: .destructive) {
                    viewModel.showPurgeConfirmation = true
                }
                .disabled(viewModel.isCalculatingCache || viewModel.isPurgingCache || viewModel.currentCacheSizeBytes == 0)
                if let status = viewModel.statusMessage {
                    Text(status).font(.footnote).foregroundStyle(palette.textSecondary)
                }
            } header: {
                Text("Storage")
            } footer: {
                Text("Removes files downloaded into XClient’s media cache. Photos and other system caches are not affected.")
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
            }
        }
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await viewModel.calculateCacheSize() }
        .confirmationDialog("Clear media cache?", isPresented: $viewModel.showPurgeConfirmation, titleVisibility: .visible) {
            Button("Clear cache", role: .destructive) { Task { await viewModel.purgeCache() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Cached media will need to be downloaded again.")
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        if let version, let build, !build.isEmpty { return "\(version) (\(build))" }
        return version ?? "Unavailable"
    }
}
