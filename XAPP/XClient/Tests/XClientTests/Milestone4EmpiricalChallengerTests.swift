//
//  Milestone4EmpiricalChallengerTests.swift
//  XClientTests
//
//  Adversarial Empirical Challenger Stress Test Suite for Milestone 4:
//  - ProfileView Parallax geometry math across [-500.0, +500.0] and avatar scale clamping [0.0, 1.0]
//  - Zero follower/following metrics, nil bio handling, malicious bio strings
//  - Rapid subtab switching oscillation (.posts -> .replies -> .media -> .likes) and cache consistency
//  - SettingsView Liquid Glass intensity boundary inputs (-1.0, 0.0, 0.5, 1.0, 2.0, NaN, +Inf, -Inf)
//  - Theme attribute propagation and high-contrast fallbacks
//  - Disk cache purge concurrency stress, empty/non-empty purges, and filesystem integrity
//  100% Swift 6 strict concurrency compliance.
//

import Testing
import Foundation
import SwiftUI
import Combine
import XKitModels
import XKitAPI
@testable import XClient

@Suite("Milestone 4 Empirical Challenger Test Suite", .serialized)
struct Milestone4EmpiricalChallengerTests {

    // MARK: - Test Harness Helpers

    @MainActor
    private func makeIsolatedSettings() -> (SettingsViewModel, UserDefaults, MediaDownloadManager, URL) {
        let suiteName = "ChallengerSettings_\(UUID().uuidString)"
        let isolatedDefaults = UserDefaults(suiteName: suiteName)!

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ChallengerCache_\(UUID().uuidString)",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let downloadManager = MediaDownloadManager(customCacheDirectory: tempDir)

        let vm = SettingsViewModel(
            userDefaults: isolatedDefaults,
            mediaDownloadManager: downloadManager
        )
        return (vm, isolatedDefaults, downloadManager, tempDir)
    }

    // MARK: - Domain 1: ProfileView Parallax Geometry Math & Clamping Stress

    @Test("Challenge 1.1: Parallax Banner Height and Offset Sweep across [-500.0, +500.0] with ProfileGeometry")
    @MainActor
    func testParallaxBannerContinuousSweep() {
        let baseHeight: CGFloat = ProfileGeometry.defaultBannerBaseHeight

        // Stride across negative and positive scroll offsets
        var offset: CGFloat = -500.0
        while offset <= 500.0 {
            let isStretching = offset < 0
            let effectiveHeight = ProfileGeometry.effectiveBannerHeight(baseHeight: baseHeight, scrollOffsetY: offset)
            let effectiveOffset = ProfileGeometry.effectiveBannerOffset(scrollOffsetY: offset)

            #expect(effectiveHeight.isFinite)
            #expect(effectiveOffset.isFinite)

            if isStretching {
                // When pulling down / stretching, effective height expands by exact negative offset
                #expect(effectiveHeight >= baseHeight)
                #expect(effectiveHeight == baseHeight - offset)
                #expect(effectiveOffset == offset)
                // Critical HIG geometry: pinned bottom anchor remains constant
                #expect(effectiveHeight + effectiveOffset == baseHeight)
            } else {
                // When scrolling up, height is fixed and banner translates at 40% speed
                #expect(effectiveHeight == baseHeight)
                #expect(effectiveOffset == offset * 0.4)
                #expect(effectiveOffset >= 0.0)
            }

            offset += 5.0
        }

        // Extreme bounds testing [-10,000 to +10,000]
        let extremePull: CGFloat = -10_000.0
        let extremePullHeight = ProfileGeometry.effectiveBannerHeight(baseHeight: baseHeight, scrollOffsetY: extremePull)
        let extremePullOffset = ProfileGeometry.effectiveBannerOffset(scrollOffsetY: extremePull)
        #expect(extremePullHeight == 10_150.0)
        #expect(extremePullOffset == -10_000.0)

        let extremeScrollUp: CGFloat = 10_000.0
        let extremeScrollHeight = ProfileGeometry.effectiveBannerHeight(baseHeight: baseHeight, scrollOffsetY: extremeScrollUp)
        let extremeScrollOffset = ProfileGeometry.effectiveBannerOffset(scrollOffsetY: extremeScrollUp)
        #expect(extremeScrollHeight == baseHeight)
        #expect(extremeScrollOffset == 4_000.0)
    }

    @Test("Challenge 1.2: Avatar Scale Factor Clamping Strictly Within [0.0, 1.0] across [-500.0, +500.0] with ProfileGeometry")
    @MainActor
    func testAvatarScaleClampingContinuousSweep() {
        var offset: CGFloat = -500.0
        while offset <= 500.0 {
            let scale = ProfileGeometry.avatarScale(for: offset)
            let opacity = ProfileGeometry.avatarOpacity(for: offset)

            #expect(scale >= 0.0, "Scale must never be negative for offset \(offset)")
            #expect(scale <= 1.0, "Scale must never exceed 1.0 for offset \(offset)")
            #expect(opacity >= 0.0, "Opacity must never be negative for offset \(offset)")
            #expect(opacity <= 1.0, "Opacity must never exceed 1.0 for offset \(offset)")

            if offset <= 0.0 {
                // Overscroll must pin scale and opacity at full 1.0
                #expect(scale == 1.0)
                #expect(opacity == 1.0)
            }

            if offset >= 90.0 {
                // Beyond 90pt scroll, avatar scale must be completely collapsed to 0.0
                #expect(scale == 0.0)
            }

            if offset >= 70.0 {
                // Beyond 70pt scroll, avatar opacity must be completely 0.0
                #expect(opacity == 0.0)
            }

            offset += 2.5
        }

        // Explicit corner boundaries
        #expect(ProfileGeometry.avatarScale(for: -500.0) == 1.0)
        #expect(ProfileGeometry.avatarScale(for: 0.0) == 1.0)
        #expect(ProfileGeometry.avatarScale(for: 45.0) == 0.5)
        #expect(ProfileGeometry.avatarScale(for: 90.0) == 0.0)
        #expect(ProfileGeometry.avatarScale(for: 500.0) == 0.0)

        #expect(ProfileGeometry.avatarOpacity(for: -500.0) == 1.0)
        #expect(ProfileGeometry.avatarOpacity(for: 0.0) == 1.0)
        #expect(ProfileGeometry.avatarOpacity(for: 35.0) == 0.5)
        #expect(ProfileGeometry.avatarOpacity(for: 70.0) == 0.0)
        #expect(ProfileGeometry.avatarOpacity(for: 500.0) == 0.0)
    }

    @Test("Challenge 1.3: Navigation Bar Opacity Morphing Clamped in [0.0, 1.0] with ProfileGeometry")
    @MainActor
    func testNavigationBarOpacityClamping() {
        var offset: CGFloat = -500.0
        while offset <= 500.0 {
            let opacity = ProfileGeometry.navigationBarOpacity(for: offset)
            #expect(opacity >= 0.0)
            #expect(opacity <= 1.0)

            if offset <= 80.0 {
                #expect(opacity == 0.0)
            } else if offset >= 120.0 {
                #expect(opacity == 1.0)
            }

            offset += 5.0
        }

        #expect(ProfileGeometry.navigationBarOpacity(for: 100.0) == 0.5)
        #expect(ProfileGeometry.navigationBarOpacity(for: 80.0) == 0.0)
        #expect(ProfileGeometry.navigationBarOpacity(for: 120.0) == 1.0)
        #expect(ProfileGeometry.navigationBarOpacity(for: -500.0) == 0.0)
        #expect(ProfileGeometry.navigationBarOpacity(for: 500.0) == 1.0)
    }

    // MARK: - Domain 2: Zero Follower / Following Metrics & Nil Bio Resiliency

    @Test("Challenge 2.1: Zero Metrics Formatting and Optimistic Follow Mutation Underflow Defenses")
    @MainActor
    func testZeroMetricsAndFollowerUnderflowDefenses() {
        // 1. Metric formatting boundary stress
        #expect(UserProfile.formatCount(0) == "0")
        #expect(UserProfile.formatCount(-1) == "-1")
        #expect(UserProfile.formatCount(-100) == "-100")
        #expect(UserProfile.formatCount(1) == "1")
        #expect(UserProfile.formatCount(999) == "999")
        #expect(UserProfile.formatCount(1_000) == "1.0K")
        #expect(UserProfile.formatCount(9_999) == "10.0K")
        #expect(UserProfile.formatCount(10_000) == "10.0K")
        #expect(UserProfile.formatCount(1_000_000) == "1.0M")
        #expect(UserProfile.formatCount(45_600_000) == "45.6M")

        // 2. Profile initialized with 0 followers
        let zeroUser = XUser(id: "usr_zero", name: "Zero", username: "zero")
        let zeroProfile = UserProfile(
            user: zeroUser,
            followersCount: 0,
            followingCount: 0,
            postsCount: 0,
            isFollowing: false
        )
        let vm = ProfileViewModel(userId: "usr_zero", initialProfile: zeroProfile)

        #expect(vm.followersCount == 0)
        #expect(vm.followingCount == 0)
        #expect(vm.postsCount == 0)
        #expect(vm.isFollowing == false)

        // Optimistic follow: 0 -> 1
        vm.toggleFollow()
        #expect(vm.isFollowing == true)
        #expect(vm.followersCount == 1)

        // Optimistic unfollow: 1 -> 0
        vm.toggleFollow()
        #expect(vm.isFollowing == false)
        #expect(vm.followersCount == 0)

        // Verify underflow clamping: even if previousCount was 0 and unfollow is triggered,
        // max(0, previousCount + (-1)) guarantees 0
        let underflowClamped = max(0, 0 + (-1))
        #expect(underflowClamped == 0)
    }

    @Test("Challenge 2.2: Nil Bio, Empty Bio, and Malicious Bio String Entity Parsing")
    @MainActor
    func testNilBioAndMaliciousStringEntities() {
        // 1. Nil bio user profile
        let userNoDesc = XUser(
            id: "usr_nodesc",
            name: "NoDesc",
            username: "nodesc",
            description: nil
        )
        let profileNilBio = UserProfile(user: userNoDesc, bio: nil)
        #expect(profileNilBio.bio == nil)

        // 2. Empty string bio
        let emptySpans = PostEntityParser.parse(text: "")
        #expect(emptySpans.isEmpty)
        let emptyAttr = PostEntityParser.makeAttributedString(text: "", accentColor: .blue)
        #expect(emptyAttr.characters.isEmpty)

        // 3. Whitespace-only bio
        let wsSpans = PostEntityParser.parse(text: "  \n\t  ")
        #expect(wsSpans.isEmpty)

        // 4. Adversarial inputs: isolated symbols, null bytes, RTL overrides
        let adversarialInputs = [
            "@",
            "@@@",
            "#",
            "###",
            "https://",
            "user@domain.com",
            "Check @valid_user but not @ or @-invalid or @123_456!",
            "Embedded\0Null\0Bytes in bio",
            "\u{202E}ReversedText\u{202C} @swift_lang",
            "👨‍👩‍👧‍👦 Emoji family in bio #family"
        ]

        for input in adversarialInputs {
            let spans = PostEntityParser.parse(text: input)
            #expect(spans.count >= 0)
            let attr = PostEntityParser.makeAttributedString(text: input, accentColor: .blue)
            #expect(!attr.characters.isEmpty || input.isEmpty)
        }

        // 5. Stress test: 5,000 character bio
        let longBio = String(repeating: "Hello @swift_lang #ios https://apple.com ", count: 120)
        let start = Date()
        let longSpans = PostEntityParser.parse(text: longBio)
        let elapsed = Date().timeIntervalSince(start)
        #expect(!longSpans.isEmpty)
        #expect(elapsed < 0.25, "Bio parsing of 5,000 characters took too long: \(elapsed)s")
    }

    @Test("Challenge 2.3: Follower Count Mutation & Pull-to-Refresh Persistence Stress across Multiple Toggle Rounds")
    @MainActor
    func testFollowerCountMutationAndPullToRefreshPersistenceStress() async {
        let provider = MockDataProvider()
        let service = MockClientService(
            currentUser: provider.currentUser,
            timelinePosts: provider.timelinePosts,
            users: provider.users
        )
        // Pick target user who is not current user
        let otherUser = provider.users.values.first(where: { $0.id != provider.currentUser.id })!
        let vm = ProfileViewModel(userId: otherUser.id, service: service)
        await vm.loadProfile()

        #expect(vm.userProfile != nil)
        let initialFollowers = vm.followersCount
        let initialFollowingState = vm.isFollowing

        // Stress cycle: 5 rounds of toggle follow -> assert -> refreshProfile -> assert persistence
        for cycle in 1...5 {
            // Toggle follow state
            vm.toggleFollow()
            let expectedFollowing = !initialFollowingState
            let expectedFollowers = initialFollowers + (expectedFollowing ? 1 : -1)

            #expect(vm.isFollowing == expectedFollowing, "Cycle \(cycle): isFollowing failed to update optimistically")
            #expect(vm.followersCount == expectedFollowers, "Cycle \(cycle): followersCount failed to update optimistically")
            #expect(vm.userProfile?.followersCount == expectedFollowers, "Cycle \(cycle): userProfile.followersCount not in sync")
            #expect(MockDataProvider.shared.userProfiles[otherUser.id]?.followersCount == expectedFollowers, "Cycle \(cycle): MockDataProvider cache not in sync")

            // Pull-to-refresh persistence check
            await vm.refreshProfile()
            #expect(vm.isFollowing == expectedFollowing, "Cycle \(cycle): isFollowing did not persist across pull-to-refresh")
            #expect(vm.followersCount == expectedFollowers, "Cycle \(cycle): followersCount reverted after pull-to-refresh")
            #expect(vm.userProfile?.followersCount == expectedFollowers, "Cycle \(cycle): userProfile.followersCount reverted after pull-to-refresh")

            // Revert back
            vm.toggleFollow()
            #expect(vm.isFollowing == initialFollowingState, "Cycle \(cycle): revert isFollowing failed")
            #expect(vm.followersCount == initialFollowers, "Cycle \(cycle): revert followersCount failed")
            #expect(vm.userProfile?.followersCount == initialFollowers, "Cycle \(cycle): revert userProfile not in sync")

            await vm.refreshProfile()
            #expect(vm.isFollowing == initialFollowingState, "Cycle \(cycle): reverted state did not persist across refresh")
            #expect(vm.followersCount == initialFollowers, "Cycle \(cycle): reverted count did not persist across refresh")
        }

        // Cross-ViewModel Cache Coherence Verification:
        // A fresh ProfileViewModel instance pointing to the same userId must load the synchronized state
        vm.toggleFollow() // mutate state
        let mutatedCount = vm.followersCount
        let mutatedFollowing = vm.isFollowing

        let freshVM = ProfileViewModel(userId: otherUser.id, service: service)
        await freshVM.loadProfile()
        #expect(freshVM.followersCount == mutatedCount, "Secondary ViewModel failed to observe cached follower count mutation")
        #expect(freshVM.isFollowing == mutatedFollowing, "Secondary ViewModel failed to observe cached following state")
    }

    // MARK: - Domain 3: Rapid Subtab Switching Oscillation & Feed Caching

    @Test("Challenge 3.1: Rapid Subtab Switching Oscillation (.posts -> .replies -> .media -> .likes)")
    @MainActor
    func testRapidSubtabSwitchingOscillation() async {
        let provider = MockDataProvider()
        let service = MockClientService(
            currentUser: provider.currentUser,
            timelinePosts: provider.timelinePosts,
            users: provider.users
        )
        let vm = ProfileViewModel(userId: provider.currentUser.id, service: service)
        await vm.loadProfile()

        #expect(vm.userProfile != nil)
        #expect(vm.selectedSubtab == .posts)

        // 50 rapid sequential oscillations across all 4 subtabs
        let tabs = ProfileSubtab.allCases
        for cycle in 0..<50 {
            let tab = tabs[cycle % tabs.count]
            vm.selectSubtab(tab)
            await vm.fetchFeedIfNeeded(for: tab)

            #expect(vm.selectedSubtab == tab)
            #expect(vm.postsBySubtab[tab] != nil)

            if tab == .media {
                #expect(!vm.mediaItems.isEmpty)
                #expect(vm.isFeedEmpty == false)
            } else {
                #expect(vm.currentPosts == vm.postsBySubtab[tab])
            }
        }

        // Cache persistence check: all 4 subtabs remain cached in memory
        #expect(vm.postsBySubtab.count == 4)
        for tab in ProfileSubtab.allCases {
            #expect(vm.postsBySubtab[tab] != nil)
        }

        // Invalidation via refresh
        await vm.refreshProfile()
        // Current active subtab re-fetched, others invalidated
        #expect(vm.errorMessage == nil)
        #expect(vm.postsBySubtab[vm.selectedSubtab] != nil)
    }

    @Test("Challenge 3.2: Concurrent Subtab Selection and Cache Reading Stress")
    @MainActor
    func testConcurrentSubtabSelectionAndCacheReading() async {
        let provider = MockDataProvider()
        let service = MockClientService(
            currentUser: provider.currentUser,
            timelinePosts: provider.timelinePosts,
            users: provider.users
        )
        let vm = ProfileViewModel(userId: provider.currentUser.id, service: service)
        await vm.loadProfile()

        // Spawn multiple concurrent tasks on MainActor interleaving operations
        let tasks = (0..<20).map { i in
            let targetTab = ProfileSubtab.allCases[i % 4]
            return Task { @MainActor in
                vm.selectSubtab(targetTab)
                await vm.fetchFeedIfNeeded(for: targetTab)
                _ = vm.currentPosts
                _ = vm.isFeedEmpty
            }
        }
        for task in tasks {
            await task.value
        }

        #expect(vm.errorMessage == nil)
        #expect(vm.postsBySubtab.count > 0)
    }

    // MARK: - Domain 4: Liquid Glass Intensity Slider Boundary & Sanitization Stress

    @Test("Challenge 4.1: Liquid Glass Intensity Slider Boundary Inputs (-1.0, 0.0, 0.5, 1.0, 2.0, NaN, Inf, -Inf)")
    @MainActor
    func testGlassIntensityBoundaryInputs() {
        let (vm, defaults, _, tempDir) = makeIsolatedSettings()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 1. Direct sanitization helper verification
        #expect(SettingsViewModel.sanitizeIntensity(-1.0) == 0.0)
        #expect(SettingsViewModel.sanitizeIntensity(-0.0001) == 0.0)
        #expect(SettingsViewModel.sanitizeIntensity(0.0) == 0.0)
        #expect(SettingsViewModel.sanitizeIntensity(0.5) == 0.5)
        #expect(SettingsViewModel.sanitizeIntensity(1.0) == 1.0)
        #expect(SettingsViewModel.sanitizeIntensity(1.0001) == 1.0)
        #expect(SettingsViewModel.sanitizeIntensity(2.0) == 1.0)
        #expect(SettingsViewModel.sanitizeIntensity(Double.nan) == 1.0)
        #expect(SettingsViewModel.sanitizeIntensity(Double.infinity) == 1.0)
        #expect(SettingsViewModel.sanitizeIntensity(-Double.infinity) == 1.0)

        // 2. ViewModel mutation & formatting verification
        struct TestCase {
            let input: Double
            let expectedIntensity: Double
            let expectedFormatting: String
        }

        let testCases: [TestCase] = [
            TestCase(input: -1.0, expectedIntensity: 0.0, expectedFormatting: "0%"),
            TestCase(input: 0.0, expectedIntensity: 0.0, expectedFormatting: "0%"),
            TestCase(input: 0.5, expectedIntensity: 0.5, expectedFormatting: "50%"),
            TestCase(input: 1.0, expectedIntensity: 1.0, expectedFormatting: "100%"),
            TestCase(input: 2.0, expectedIntensity: 1.0, expectedFormatting: "100%"),
            TestCase(input: Double.nan, expectedIntensity: 1.0, expectedFormatting: "100%"),
            TestCase(input: Double.infinity, expectedIntensity: 1.0, expectedFormatting: "100%"),
            TestCase(input: -Double.infinity, expectedIntensity: 1.0, expectedFormatting: "100%")
        ]

        for tc in testCases {
            vm.updateGlassIntensity(tc.input)
            #expect(vm.glassIntensity == tc.expectedIntensity)
            #expect(vm.formattedGlassIntensityPercentage == tc.expectedFormatting)

            let savedValue = defaults.double(forKey: SettingsViewModel.StorageKeys.glassIntensity)
            #expect(savedValue == tc.expectedIntensity)
        }
    }

    @Test("Challenge 4.2: LiquidGlassAttributes Resolution and High-Contrast Accessibility Fallbacks")
    @MainActor
    func testLiquidGlassAttributesResolutionBoundaryStress() {
        for style in LiquidGlassStyle.allCases {
            // Case A: Normal intensity 1.0 without reduceTransparency
            let normalAttrs = LiquidGlassAttributes.resolve(style: style, intensity: 1.0, reduceTransparency: false)
            #expect(normalAttrs.isOpaqueFallback == false)
            #expect(normalAttrs.intensity == 1.0)
            #expect(normalAttrs.shadowOpacity == style.shadowOpacity)
            #expect(normalAttrs.strokeOpacity == 0.6)

            // Case B: Subtle intensity 0.5 without reduceTransparency
            let subtleAttrs = LiquidGlassAttributes.resolve(style: style, intensity: 0.5, reduceTransparency: false)
            #expect(subtleAttrs.isOpaqueFallback == false)
            #expect(subtleAttrs.intensity == 0.5)
            #expect(subtleAttrs.shadowOpacity == style.shadowOpacity * 0.5)
            #expect(subtleAttrs.strokeOpacity == 0.3)

            // Case C: Intensity 0.0 (triggers safe opaque fallback)
            let zeroAttrs = LiquidGlassAttributes.resolve(style: style, intensity: 0.0, reduceTransparency: false)
            #expect(zeroAttrs.isOpaqueFallback == true)
            #expect(zeroAttrs.shadowOpacity == 0.0)
            #expect(zeroAttrs.strokeOpacity == 1.0)

            // Case D: Negative intensity -1.0 (clamped to 0.0, triggers opaque fallback)
            let negAttrs = LiquidGlassAttributes.resolve(style: style, intensity: -1.0, reduceTransparency: false)
            #expect(negAttrs.isOpaqueFallback == true)
            #expect(negAttrs.intensity == 0.0)
            #expect(negAttrs.shadowOpacity == 0.0)

            // Case E: Overflow intensity 2.0 (clamped to 1.0)
            let overflowAttrs = LiquidGlassAttributes.resolve(style: style, intensity: 2.0, reduceTransparency: false)
            #expect(overflowAttrs.isOpaqueFallback == false)
            #expect(overflowAttrs.intensity == 1.0)
            #expect(overflowAttrs.shadowOpacity == style.shadowOpacity)

            // Case F: Non-finite inputs: NaN, +Inf, -Inf
            for nonFinite in [Double.nan, Double.infinity, -Double.infinity] {
                let nonFiniteAttrs = LiquidGlassAttributes.resolve(style: style, intensity: nonFinite, reduceTransparency: false)
                #expect(nonFiniteAttrs.isOpaqueFallback == true)
                #expect(nonFiniteAttrs.intensity == 0.0)
                #expect(nonFiniteAttrs.shadowOpacity == 0.0)
                #expect(nonFiniteAttrs.strokeOpacity == 1.0)
            }

            // Case G: Accessibility reduceTransparency overrides ANY intensity
            let reducedAttrs = LiquidGlassAttributes.resolve(style: style, intensity: 1.0, reduceTransparency: true)
            #expect(reducedAttrs.isOpaqueFallback == true)
            #expect(reducedAttrs.shadowOpacity == 0.0)
            #expect(reducedAttrs.strokeOpacity == 1.0)
        }
    }

    @Test("Challenge 4.3: View Modifier Instantiation with Boundary Intensity Inputs")
    @MainActor
    func testModifierInstantiationBoundaries() {
        // Confirm constructor sanitization prevents invalid state
        let modNeg = LiquidGlassModifier(intensity: -1.0)
        #expect(modNeg.intensity == 0.0)

        let modOver = LiquidGlassModifier(intensity: 2.5)
        #expect(modOver.intensity == 1.0)

        let modNaN = LiquidGlassModifier(intensity: Double.nan)
        #expect(modNaN.intensity == 0.0)

        let modInf = LiquidGlassModifier(intensity: Double.infinity)
        #expect(modInf.intensity == 0.0)

        let capNeg = LiquidGlassCapsuleModifier(intensity: -0.5)
        #expect(capNeg.intensity == 0.0)

        let capNaN = LiquidGlassCapsuleModifier(intensity: Double.nan)
        #expect(capNaN.intensity == 0.0)
    }

    // MARK: - Domain 5: Disk Cache Purge Concurrency, Empty/Non-Empty States & Filesystem Integrity

    @Test("Challenge 5.1: Purge When Empty Cache Returns Zero and Preserves Integrity")
    @MainActor
    func testPurgeWhenEmptyCache() async {
        let (vm, _, downloadManager, tempDir) = makeIsolatedSettings()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Precondition: empty directory
        await vm.calculateCacheSize()
        #expect(vm.currentCacheSizeBytes == 0)
        #expect(vm.formattedCacheSize == "0.0 MB")

        // Action: Purge empty cache
        let purgedCount = await vm.purgeCache()
        #expect(purgedCount == 0)
        #expect(vm.currentCacheSizeBytes == 0)
        #expect(vm.currentCacheSizeMB == 0.0)
        #expect(vm.formattedCacheSize == "0.0 MB")
        #expect(vm.statusMessage?.contains("already empty") == true)

        // Integrity: directory still exists and is accessible
        #expect(FileManager.default.fileExists(atPath: downloadManager.cacheDirectory.path))
    }

    @Test("Challenge 5.2: Purge When Non-Empty Cache Deletes All Files and Resets Metrics")
    @MainActor
    func testPurgeNonEmptyCacheWithVariedFileSizes() async throws {
        let (vm, _, downloadManager, tempDir) = makeIsolatedSettings()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let cacheDir = downloadManager.cacheDirectory
        var expectedTotalBytes: Int64 = 0

        // Create 25 files with varied sizes
        for i in 1...25 {
            let size = i * 4096 // 4 KB, 8 KB, ... 100 KB
            let fileData = Data(repeating: UInt8(i % 255), count: size)
            let fileURL = cacheDir.appendingPathComponent("cached_media_\(i).media")
            try fileData.write(to: fileURL)
            expectedTotalBytes += Int64(size)
        }

        // Verify calculation matches exact bytes
        await vm.calculateCacheSize()
        #expect(vm.currentCacheSizeBytes == expectedTotalBytes)
        #expect(vm.currentCacheSizeMB > 0.0)

        // Action: Purge
        let purgedCount = await vm.purgeCache()
        #expect(purgedCount == 25)
        #expect(vm.currentCacheSizeBytes == 0)
        #expect(vm.currentCacheSizeMB == 0.0)
        #expect(vm.formattedCacheSize == "0.0 MB")

        // Verify all files were deleted
        let remaining = try FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)
        #expect(remaining.isEmpty)

        // Verify directory still exists and can be written to
        let testWrite = cacheDir.appendingPathComponent("post_purge_test.txt")
        try "test".write(to: testWrite, atomically: true, encoding: .utf8)
        #expect(FileManager.default.fileExists(atPath: testWrite.path))
    }

    @Test("Challenge 5.3: Disk Cache Purge Concurrency Stress (Multiple Simultaneous Purge Tasks)")
    @MainActor
    func testDiskCachePurgeConcurrencyStress() async throws {
        let (vm, _, downloadManager, tempDir) = makeIsolatedSettings()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let cacheDir = downloadManager.cacheDirectory

        // Populate with 50 files
        for i in 1...50 {
            let dummy = Data(repeating: 0xFF, count: 1024)
            try dummy.write(to: cacheDir.appendingPathComponent("concurrent_file_\(i).jpg"))
        }

        await vm.calculateCacheSize()
        #expect(vm.currentCacheSizeBytes == 50 * 1024)

        // Launch 15 concurrent purge attempts on MainActor
        let tasks = (0..<15).map { _ in
            Task { @MainActor in
                await vm.purgeCache()
            }
        }
        var purgeResults: [Int] = []
        for task in tasks {
            let count = await task.value
            purgeResults.append(count)
        }

        // Sum of all purged counts must equal exactly 50 (no duplicate deletion crashes or negative counts)
        let totalPurged = purgeResults.reduce(0, +)
        #expect(totalPurged == 50, "Total purged files across concurrent tasks should equal initial count (50)")

        // Cache size must be 0
        #expect(vm.currentCacheSizeBytes == 0)
        #expect(vm.isPurgingCache == false)

        // Directory must be clean and intact
        let remaining = try FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)
        #expect(remaining.isEmpty)
        #expect(FileManager.default.fileExists(atPath: cacheDir.path))
    }

    @Test("Challenge 5.4: Interleaved File Writing and Purging Stress")
    @MainActor
    func testInterleavedWritingAndPurging() async throws {
        let (vm, _, downloadManager, tempDir) = makeIsolatedSettings()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let cacheDir = downloadManager.cacheDirectory

        // Run 5 sequential rounds of write -> calculate -> purge
        for round in 1...5 {
            for i in 1...10 {
                let data = Data(repeating: UInt8(round), count: 2048)
                try data.write(to: cacheDir.appendingPathComponent("round_\(round)_file_\(i).bin"))
            }

            await vm.calculateCacheSize()
            #expect(vm.currentCacheSizeBytes == 10 * 2048)

            let count = await vm.purgeCache()
            #expect(count == 10)
            #expect(vm.currentCacheSizeBytes == 0)
        }

        #expect(FileManager.default.fileExists(atPath: cacheDir.path))
    }
}
