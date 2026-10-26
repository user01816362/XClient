//
//  SettingsViewModel.swift
//  XClient
//
//  MainActor ViewModel managing application user preferences, appearance themes,
//  Liquid Glass intensity, background auto-refresh intervals, and disk cache metrics.
//  100% Swift 6 strict concurrency compliance.
//

import SwiftUI
import Combine
import Foundation

/// MainActor coordinator managing user preferences, persistence, and cache lifecycle.
@MainActor
public final class SettingsViewModel: ObservableObject, Sendable {

    // MARK: - Persistence Keys
    public enum StorageKeys {
        public static let themePreference = "app_theme_preference"
        public static let glassIntensity = "liquid_glass_intensity"
        public static let pollingInterval = "timeline_polling_interval"
    }

    // MARK: - Published State
    @Published public var selectedTheme: AppThemePreference {
        didSet {
            userDefaults.set(selectedTheme.rawValue, forKey: StorageKeys.themePreference)
        }
    }

    @Published public var glassIntensity: Double {
        didSet {
            let sanitized = Self.sanitizeIntensity(glassIntensity)
            if sanitized != glassIntensity {
                glassIntensity = sanitized
            }
            userDefaults.set(glassIntensity, forKey: StorageKeys.glassIntensity)
        }
    }

    @Published public var autoRefreshInterval: PollingInterval {
        didSet {
            userDefaults.set(autoRefreshInterval.rawValue, forKey: StorageKeys.pollingInterval)
            onPollingIntervalChanged?(autoRefreshInterval)
        }
    }

    // MARK: - Cache & Storage State
    @Published public private(set) var currentCacheSizeBytes: Int64 = 0
    @Published public private(set) var currentCacheSizeMB: Double = 0.0
    @Published public private(set) var isCalculatingCache: Bool = false
    @Published public private(set) var isPurgingCache: Bool = false
    @Published public private(set) var lastPurgeCount: Int? = nil
    @Published public private(set) var statusMessage: String? = nil

    // MARK: - Alert & Modal Presentation State
    @Published public var showPurgeConfirmation: Bool = false
    @Published public var showResetConfirmation: Bool = false

    // MARK: - Dependencies
    private let userDefaults: UserDefaults
    private let mediaDownloadManager: MediaDownloadManager
    public var onPollingIntervalChanged: (@Sendable (PollingInterval) -> Void)?

    // MARK: - Initializer
    public init(
        userDefaults: UserDefaults = .standard,
        mediaDownloadManager: MediaDownloadManager = .shared,
        onPollingIntervalChanged: (@Sendable (PollingInterval) -> Void)? = nil
    ) {
        self.userDefaults = userDefaults
        self.mediaDownloadManager = mediaDownloadManager
        self.onPollingIntervalChanged = onPollingIntervalChanged

        // 1. Restore Theme Preference
        if let storedThemeRaw = userDefaults.string(forKey: StorageKeys.themePreference),
           let storedTheme = AppThemePreference(rawValue: storedThemeRaw) {
            self.selectedTheme = storedTheme
        } else {
            self.selectedTheme = .system
        }

        // 2. Restore Glass Intensity
        if userDefaults.object(forKey: StorageKeys.glassIntensity) != nil {
            let rawIntensity = userDefaults.double(forKey: StorageKeys.glassIntensity)
            self.glassIntensity = Self.sanitizeIntensity(rawIntensity)
        } else {
            self.glassIntensity = 1.0
        }

        // 3. Restore Polling Interval
        if userDefaults.object(forKey: StorageKeys.pollingInterval) != nil {
            let rawInterval = userDefaults.double(forKey: StorageKeys.pollingInterval)
            self.autoRefreshInterval = PollingInterval(rawValue: rawInterval) ?? .thirtySeconds
        } else {
            self.autoRefreshInterval = .thirtySeconds
        }
    }

    // MARK: - Defensive Sanitization
    public static func sanitizeIntensity(_ value: Double) -> Double {
        guard value.isFinite && !value.isNaN else {
            return 1.0
        }
        return max(0.0, min(1.0, value))
    }

    // MARK: - Formatted Presentation Helpers
    public var formattedGlassIntensityPercentage: String {
        let percent = Int(round(glassIntensity * 100))
        return "\(percent)%"
    }

    public var formattedCacheSize: String {
        if currentCacheSizeBytes == 0 {
            return "0.0 MB"
        } else if currentCacheSizeMB < 0.1 && currentCacheSizeBytes > 0 {
            return "< 0.1 MB"
        } else {
            return String(format: "%.1f MB", currentCacheSizeMB)
        }
    }

    // MARK: - Asynchronous Cache Operations

    /// Asynchronously calculates total cached media size on disk.
    public func calculateCacheSize() async {
        guard !isCalculatingCache else { return }
        isCalculatingCache = true

        let bytes = mediaDownloadManager.cacheSizeInBytes()
        self.currentCacheSizeBytes = bytes
        self.currentCacheSizeMB = Double(bytes) / (1024.0 * 1024.0)
        self.isCalculatingCache = false
    }

    /// Purges all cached media files from disk via MediaDownloadManager.
    @discardableResult
    public func purgeCache() async -> Int {
        guard !isPurgingCache else { return 0 }
        isPurgingCache = true
        statusMessage = nil

        do {
            let count = try await mediaDownloadManager.clearCache()
            self.lastPurgeCount = count
            self.currentCacheSizeBytes = 0
            self.currentCacheSizeMB = 0.0
            self.statusMessage = count > 0 ? "Purged \(count) cached media items." : "Cache is already empty."
            self.isPurgingCache = false
            return count
        } catch {
            self.statusMessage = "Purge failed: \(error.localizedDescription)"
            self.isPurgingCache = false
            return 0
        }
    }

    // MARK: - Preference Mutations

    public func updateTheme(_ theme: AppThemePreference) {
        self.selectedTheme = theme
    }

    public func updateGlassIntensity(_ intensity: Double) {
        self.glassIntensity = Self.sanitizeIntensity(intensity)
    }

    public func updatePollingInterval(_ interval: PollingInterval) {
        self.autoRefreshInterval = interval
    }

    /// Resets all user preferences to default out-of-the-box settings.
    public func resetToDefaults() {
        self.selectedTheme = .system
        self.glassIntensity = 1.0
        self.autoRefreshInterval = .thirtySeconds
        userDefaults.removeObject(forKey: StorageKeys.themePreference)
        userDefaults.removeObject(forKey: StorageKeys.glassIntensity)
        userDefaults.removeObject(forKey: StorageKeys.pollingInterval)
        self.statusMessage = "Settings restored to defaults."
    }
}
