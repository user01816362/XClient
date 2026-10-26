//
//  SettingsTests.swift
//  XClientTests
//
//  Automated Unit & Component Tests for Milestone 4 (Feature F9):
//  Theme preference persistence, Liquid Glass intensity range clamping & sanitization,
//  auto-refresh polling interval synchronization, cache size calculation and purge,
//  and Tier 4 Scenario 6.
//  100% Swift 6 strict concurrency compliance.
//

import Testing
import Foundation
import SwiftUI
import XKitModels
@testable import XClient

@Suite("Milestone 4: Settings Panel & Customization Tests (Feature F9)", .serialized)
struct SettingsTests {

    @MainActor
    private func makeIsolatedViewModel() -> (SettingsViewModel, UserDefaults, MediaDownloadManager, URL) {
        let suiteName = "SettingsTests_\(UUID().uuidString)"
        let isolatedDefaults = UserDefaults(suiteName: suiteName)!

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SettingsTestCache_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let downloadManager = MediaDownloadManager(customCacheDirectory: tempDir)

        let vm = SettingsViewModel(
            userDefaults: isolatedDefaults,
            mediaDownloadManager: downloadManager
        )
        return (vm, isolatedDefaults, downloadManager, tempDir)
    }

    // MARK: - Tier 1: Feature Coverage Tests

    @Test("T1.1: Verify Default Settings Initialization")
    @MainActor
    func testDefaultSettingsInitialization() {
        let (vm, _, _, tempDir) = makeIsolatedViewModel()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        #expect(vm.selectedTheme == .system)
        #expect(vm.glassIntensity == 1.0)
        #expect(vm.autoRefreshInterval == .thirtySeconds)
        #expect(vm.formattedGlassIntensityPercentage == "100%")
        #expect(vm.isCalculatingCache == false)
        #expect(vm.isPurgingCache == false)
    }

    @Test("T1.2: Verify Theme Preference Persistence Round-Trip")
    @MainActor
    func testThemePreferencePersistence() {
        let (vm, defaults, _, tempDir) = makeIsolatedViewModel()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 1. Dark Dim
        vm.updateTheme(.darkDim)
        #expect(vm.selectedTheme == .darkDim)
        #expect(defaults.string(forKey: SettingsViewModel.StorageKeys.themePreference) == "darkDim")

        // 2. Dark Lights Out
        vm.updateTheme(.darkLightsOut)
        #expect(vm.selectedTheme == .darkLightsOut)
        #expect(defaults.string(forKey: SettingsViewModel.StorageKeys.themePreference) == "darkLightsOut")

        // 3. Light
        vm.updateTheme(.light)
        #expect(vm.selectedTheme == .light)
        #expect(defaults.string(forKey: SettingsViewModel.StorageKeys.themePreference) == "light")
    }

    @Test("T1.3: Verify Liquid Glass Intensity Percentage Formatting")
    @MainActor
    func testGlassIntensityFormatting() {
        let (vm, _, _, tempDir) = makeIsolatedViewModel()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        vm.updateGlassIntensity(1.0)
        #expect(vm.formattedGlassIntensityPercentage == "100%")

        vm.updateGlassIntensity(0.75)
        #expect(vm.formattedGlassIntensityPercentage == "75%")

        vm.updateGlassIntensity(0.50)
        #expect(vm.formattedGlassIntensityPercentage == "50%")

        vm.updateGlassIntensity(0.0)
        #expect(vm.formattedGlassIntensityPercentage == "0%")
    }

    @Test("T1.4: Verify Polling Interval Persistence and Display Names")
    @MainActor
    func testPollingIntervalPersistenceAndDisplayNames() {
        let (vm, defaults, _, tempDir) = makeIsolatedViewModel()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        #expect(PollingInterval.fifteenSeconds.displayName == "15 seconds")
        #expect(PollingInterval.thirtySeconds.displayName == "30 seconds")
        #expect(PollingInterval.oneMinute.displayName == "1 minute")
        #expect(PollingInterval.twoMinutes.displayName == "2 minutes")
        #expect(PollingInterval.manual.displayName == "Manual (Off)")

        vm.updatePollingInterval(.oneMinute)
        #expect(vm.autoRefreshInterval == .oneMinute)
        #expect(defaults.double(forKey: SettingsViewModel.StorageKeys.pollingInterval) == 60.0)
    }

    @Test("T1.5: Verify Polling Interval Callback Invocation")
    @MainActor
    func testPollingIntervalCallback() {
        let (vm, _, _, tempDir) = makeIsolatedViewModel()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        final class Box: @unchecked Sendable {
            var interval: PollingInterval?
        }
        let box = Box()
        vm.onPollingIntervalChanged = { interval in
            box.interval = interval
        }

        vm.updatePollingInterval(.fifteenSeconds)
        #expect(box.interval == .fifteenSeconds)
    }

    @Test("T1.6: Verify LiveSampleCardState Interactive Mutations and Counter Transitions")
    @MainActor
    func testLiveSampleCardStateMutations() {
        let state = LiveSampleCardState()
        #expect(state.isLiked == false)
        #expect(state.isReposted == false)
        #expect(state.isBookmarked == false)
        #expect(state.likeCount == 42)
        #expect(state.repostCount == 12)

        // Like toggle mutation
        state.isLiked.toggle()
        state.likeCount += state.isLiked ? 1 : -1
        #expect(state.isLiked == true)
        #expect(state.likeCount == 43)

        state.isLiked.toggle()
        state.likeCount += state.isLiked ? 1 : -1
        #expect(state.isLiked == false)
        #expect(state.likeCount == 42)

        // Repost toggle mutation
        state.isReposted.toggle()
        state.repostCount += state.isReposted ? 1 : -1
        #expect(state.isReposted == true)
        #expect(state.repostCount == 13)

        state.isReposted.toggle()
        state.repostCount += state.isReposted ? 1 : -1
        #expect(state.isReposted == false)
        #expect(state.repostCount == 12)

        // Bookmark toggle mutation
        state.isBookmarked.toggle()
        #expect(state.isBookmarked == true)
        state.isBookmarked.toggle()
        #expect(state.isBookmarked == false)
    }

    // MARK: - Tier 2: Boundary & Corner Cases

    @Test("T2.1: Verify Liquid Glass Intensity Clamping Upper Bound")
    @MainActor
    func testGlassIntensityClampUpper() {
        let (vm, _, _, tempDir) = makeIsolatedViewModel()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        vm.updateGlassIntensity(1.85)
        #expect(vm.glassIntensity == 1.0)
        #expect(vm.formattedGlassIntensityPercentage == "100%")
    }

    @Test("T2.2: Verify Liquid Glass Intensity Clamping Lower Bound")
    @MainActor
    func testGlassIntensityClampLower() {
        let (vm, _, _, tempDir) = makeIsolatedViewModel()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        vm.updateGlassIntensity(-0.5)
        #expect(vm.glassIntensity == 0.0)
        #expect(vm.formattedGlassIntensityPercentage == "0%")
    }

    @Test("T2.3: Verify Liquid Glass Intensity Defensive NaN and Infinity Sanitization")
    @MainActor
    func testGlassIntensityNaNSanitization() {
        let sanitizedNaN = SettingsViewModel.sanitizeIntensity(Double.nan)
        #expect(sanitizedNaN == 1.0)

        let sanitizedInf = SettingsViewModel.sanitizeIntensity(Double.infinity)
        #expect(sanitizedInf == 1.0)

        let sanitizedNegInf = SettingsViewModel.sanitizeIntensity(-Double.infinity)
        #expect(sanitizedNegInf == 1.0)
    }

    @Test("T2.4: Verify Cache Size Formatting with Zero Bytes")
    @MainActor
    func testCacheSizeZeroFormatting() {
        let (vm, _, _, tempDir) = makeIsolatedViewModel()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        #expect(vm.formattedCacheSize == "0.0 MB")
    }

    @Test("T2.5: Verify Purge on Empty Cache Returns Zero Items Cleanly")
    @MainActor
    func testPurgeEmptyCache() async {
        let (vm, _, _, tempDir) = makeIsolatedViewModel()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let count = await vm.purgeCache()
        #expect(count == 0)
        #expect(vm.currentCacheSizeBytes == 0)
        #expect(vm.currentCacheSizeMB == 0.0)
        #expect(vm.statusMessage?.contains("already empty") == true)
    }

    @Test("T2.6: Verify Reset Preferences to Defaults Action")
    @MainActor
    func testResetToDefaults() {
        let (vm, defaults, _, tempDir) = makeIsolatedViewModel()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Mutate away from defaults
        vm.updateTheme(.darkLightsOut)
        vm.updateGlassIntensity(0.35)
        vm.updatePollingInterval(.twoMinutes)

        #expect(vm.selectedTheme == .darkLightsOut)
        #expect(vm.glassIntensity == 0.35)
        #expect(vm.autoRefreshInterval == .twoMinutes)

        // Reset
        vm.resetToDefaults()

        #expect(vm.selectedTheme == .system)
        #expect(vm.glassIntensity == 1.0)
        #expect(vm.autoRefreshInterval == .thirtySeconds)
        #expect(defaults.object(forKey: SettingsViewModel.StorageKeys.themePreference) == nil)
        #expect(defaults.object(forKey: SettingsViewModel.StorageKeys.glassIntensity) == nil)
        #expect(defaults.object(forKey: SettingsViewModel.StorageKeys.pollingInterval) == nil)
    }

    @Test("T2.7: Verify Cache Size Formatting for Sub-100KB Non-Zero Values")
    @MainActor
    func testCacheSizeSubHundredKBFormatting() async throws {
        let (vm, _, downloadManager, tempDir) = makeIsolatedViewModel()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Write a 32 KB dummy file into cache directory (< 0.1 MB)
        let cacheDir = downloadManager.cacheDirectory
        let dummyData = Data(repeating: 0xEE, count: 32 * 1024)
        let dummyFileURL = cacheDir.appendingPathComponent("sub_100kb_sample.dat")
        try dummyData.write(to: dummyFileURL)

        await vm.calculateCacheSize()
        #expect(vm.currentCacheSizeBytes == 32 * 1024)
        #expect(vm.currentCacheSizeMB < 0.1)
        #expect(vm.formattedCacheSize == "< 0.1 MB")
    }

    @Test("T2.8: Verify SettingsViewModel Initialization Defenses with Corrupted UserDefaults")
    @MainActor
    func testSettingsInitializationDefensesWithCorruptedStorage() {
        let suiteName = "CorruptedSettingsTest_\(UUID().uuidString)"
        let isolatedDefaults = UserDefaults(suiteName: suiteName)!
        isolatedDefaults.set("unknown_corrupted_theme_value", forKey: SettingsViewModel.StorageKeys.themePreference)
        isolatedDefaults.set(3.85, forKey: SettingsViewModel.StorageKeys.glassIntensity)
        isolatedDefaults.set(-999.0, forKey: SettingsViewModel.StorageKeys.pollingInterval)

        let vm = SettingsViewModel(userDefaults: isolatedDefaults)

        // Theme should defensively fall back to .system
        #expect(vm.selectedTheme == .system)
        // Glass intensity should clamp upper bound to 1.0
        #expect(vm.glassIntensity == 1.0)
        // Polling interval should fall back to .thirtySeconds
        #expect(vm.autoRefreshInterval == .thirtySeconds)
    }

    // MARK: - Tier 3: Cross-Feature Pairwise Interactions

    @Test("T3.1: Settings Theme Preference Resolves Exact ColorPalette Tokens")
    @MainActor
    func testSettingsThemeResolvesColorPalette() {
        // Light
        let lightPalette = ColorPalette.resolve(preference: .light, systemScheme: .light)
        #expect(lightPalette == ColorPalette.light)

        // Dark Dim
        let dimPalette = ColorPalette.resolve(preference: .darkDim, systemScheme: .light)
        #expect(dimPalette == ColorPalette.darkDim)

        // Dark Lights Out
        let lightsOutPalette = ColorPalette.resolve(preference: .darkLightsOut, systemScheme: .light)
        #expect(lightsOutPalette == ColorPalette.darkLightsOut)
    }

    @Test("T3.2: Settings Glass Intensity Directly Affects LiquidGlassAttributes Resolution")
    @MainActor
    func testSettingsGlassIntensityAffectsAttributes() {
        let fullAttrs = LiquidGlassAttributes.resolve(style: .standard, intensity: 1.0, reduceTransparency: false)
        #expect(fullAttrs.isOpaqueFallback == false)
        #expect(fullAttrs.intensity == 1.0)
        #expect(fullAttrs.shadowOpacity > 0.0)

        let halfAttrs = LiquidGlassAttributes.resolve(style: .standard, intensity: 0.5, reduceTransparency: false)
        #expect(halfAttrs.intensity == 0.5)
        #expect(halfAttrs.shadowOpacity < fullAttrs.shadowOpacity)

        let offAttrs = LiquidGlassAttributes.resolve(style: .standard, intensity: 0.0, reduceTransparency: false)
        #expect(offAttrs.isOpaqueFallback == true) // Clamped <= 0.05 triggers safe opaque fallback
    }

    @Test("T3.3: Disk Cache Calculation and Purge via MediaDownloadManager")
    @MainActor
    func testDiskCacheCalculationAndPurge() async throws {
        let (vm, _, downloadManager, tempDir) = makeIsolatedViewModel()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Write a 1MB dummy file into cache directory
        let cacheDir = downloadManager.cacheDirectory
        let dummyData = Data(repeating: 0xAA, count: 1024 * 1024)
        let dummyFileURL = cacheDir.appendingPathComponent("test_cache_file.media")
        try dummyData.write(to: dummyFileURL)

        // 1. Calculate
        await vm.calculateCacheSize()
        #expect(vm.currentCacheSizeBytes == 1024 * 1024)
        #expect(vm.currentCacheSizeMB >= 1.0)
        #expect(vm.formattedCacheSize.contains("1.0 MB"))

        // 2. Purge
        let purged = await vm.purgeCache()
        #expect(purged == 1)
        #expect(vm.currentCacheSizeBytes == 0)
        #expect(vm.currentCacheSizeMB == 0.0)
        #expect(vm.formattedCacheSize == "0.0 MB")
        #expect(!FileManager.default.fileExists(atPath: dummyFileURL.path))
    }

    @Test("T3.4: Settings Glass Intensity Opaque Fallback Under Accessibility Reduce Transparency")
    @MainActor
    func testSettingsGlassIntensityUnderAccessibilityReduceTransparency() {
        // Even with max glass intensity (1.0), reduceTransparency must enforce opaque fallback
        let attrs = LiquidGlassAttributes.resolve(style: .standard, intensity: 1.0, reduceTransparency: true)
        #expect(attrs.isOpaqueFallback == true)
        #expect(attrs.shadowOpacity == 0.0)

        // At 50% glass intensity with reduceTransparency
        let halfAttrs = LiquidGlassAttributes.resolve(style: .standard, intensity: 0.5, reduceTransparency: true)
        #expect(halfAttrs.isOpaqueFallback == true)
        #expect(halfAttrs.shadowOpacity == 0.0)
    }

    // MARK: - Tier 4: Real-World Application Scenario

    @Test("T4.1: Scenario 6 - Settings Customization, Appearance & Cache Purging Flow")
    @MainActor
    func testScenario6_SettingsCustomizationAppearanceAndCachePurging() async throws {
        let (vm, defaults, downloadManager, tempDir) = makeIsolatedViewModel()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Step 1: User switches theme to Dark Lights Out
        vm.updateTheme(.darkLightsOut)
        #expect(vm.selectedTheme == .darkLightsOut)

        // Step 2: User adjusts Liquid Glass intensity to 75%
        vm.updateGlassIntensity(0.75)
        #expect(vm.formattedGlassIntensityPercentage == "75%")

        // Step 3: User configures auto-refresh polling interval to 15 seconds
        vm.updatePollingInterval(.fifteenSeconds)
        #expect(vm.autoRefreshInterval == .fifteenSeconds)

        // Step 4: Add file to cache and inspect cache metrics
        let testData = Data(repeating: 0x42, count: 512 * 1024) // 512 KB
        let testFile = downloadManager.cacheDirectory.appendingPathComponent("cached_asset.jpg")
        try testData.write(to: testFile)

        await vm.calculateCacheSize()
        #expect(vm.currentCacheSizeBytes == 512 * 1024)
        #expect(vm.formattedCacheSize.contains("0.5 MB"))

        // Step 5: Execute cache purge with confirmation simulation
        vm.showPurgeConfirmation = true
        #expect(vm.showPurgeConfirmation == true)

        let purgeCount = await vm.purgeCache()
        vm.showPurgeConfirmation = false
        #expect(purgeCount == 1)
        #expect(vm.currentCacheSizeBytes == 0)

        // Step 6: Verify all customizations persist across a brand-new ViewModel instance
        let restoredVM = SettingsViewModel(
            userDefaults: defaults,
            mediaDownloadManager: downloadManager
        )
        #expect(restoredVM.selectedTheme == .darkLightsOut)
        #expect(restoredVM.glassIntensity == 0.75)
        #expect(restoredVM.autoRefreshInterval == .fifteenSeconds)
    }
}
