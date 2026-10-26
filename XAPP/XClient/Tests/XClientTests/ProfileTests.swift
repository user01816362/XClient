//
//  ProfileTests.swift
//  XClientTests
//
//  Automated Unit & Component Tests for Milestone 4 (Feature F7):
//  User profile surface loading, subtab filtering (.posts, .replies, .media, .likes),
//  bio entity parsing, follower count optimistic mutation and rollback, and Tier 4 Scenario 4.
//  100% Swift 6 strict concurrency compliance.
//

import Testing
import Foundation
import SwiftUI
import XKitModels
import XKitAPI
@testable import XClient

@Suite("Milestone 4: User Profile Surface Tests (Feature F7)", .serialized)
struct ProfileTests {

    // MARK: - Tier 1: Feature Coverage Tests

    @Test("T1.1: Verify Fetch User Profile Success with Complete Metadata")
    @MainActor
    func testFetchUserProfileSuccess() async throws {
        let provider = MockDataProvider()
        let service = MockClientService(
            currentUser: provider.currentUser,
            timelinePosts: provider.timelinePosts,
            users: provider.users
        )
        let profile = provider.currentProfile
        #expect(profile.name == "Liquid Glass")
        #expect(profile.username == "liquidglass")
        #expect(profile.isVerified == true)
        #expect(profile.joinedDateString.contains("Joined"))
        #expect(profile.followersCount >= 0)
        #expect(profile.followingCount >= 0)

        let fetchedUser = try await service.fetchUserProfile(id: provider.currentUser.id)
        #expect(fetchedUser.id == provider.currentUser.id)
        #expect(fetchedUser.name == "Liquid Glass")
    }

    @Test("T1.2: Verify Subtab Switching Loads Corresponding Post Feeds and Caches")
    @MainActor
    func testSubtabSwitchingLoadsCorrespondingFeeds() async throws {
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
        #expect(!vm.currentPosts.isEmpty)
        #expect(vm.postsBySubtab[.posts] != nil)

        // Switch to .replies
        vm.selectSubtab(.replies)
        await vm.fetchFeedIfNeeded(for: .replies)
        #expect(vm.selectedSubtab == .replies)
        #expect(vm.postsBySubtab[.replies] != nil)

        // Switch to .media
        vm.selectSubtab(.media)
        await vm.fetchFeedIfNeeded(for: .media)
        #expect(vm.selectedSubtab == .media)
        #expect(!vm.mediaItems.isEmpty)

        // Switch to .likes
        vm.selectSubtab(.likes)
        await vm.fetchFeedIfNeeded(for: .likes)
        #expect(vm.selectedSubtab == .likes)
        #expect(vm.postsBySubtab[.likes] != nil)

        // Verify caching: all 4 subtabs populated
        #expect(vm.postsBySubtab.count == 4)
    }

    @Test("T1.3: Verify Bio Mention, Hashtag, and URL Entity Extraction")
    @MainActor
    func testBioEntityParsing() throws {
        let bio = "Crafting native Apple experiences with Liquid Glass materials. Follow @swift_lang and #SwiftUI! Visit https://developer.apple.com"

        let spans = PostEntityParser.parse(text: bio)
        #expect(!spans.isEmpty)

        let hasMention = spans.contains { span in
            if case .mention(let username) = span.type {
                return username == "swift_lang"
            }
            return false
        }
        #expect(hasMention)

        let hasHashtag = spans.contains { span in
            if case .hashtag(let tag) = span.type {
                return tag == "SwiftUI"
            }
            return false
        }
        #expect(hasHashtag)

        let hasURL = spans.contains { span in
            if case .url(let url, _) = span.type {
                return url.host == "developer.apple.com"
            }
            return false
        }
        #expect(hasURL)

        let attributed = PostEntityParser.makeAttributedString(text: bio, accentColor: .blue)
        #expect(!attributed.characters.isEmpty)
    }

    @Test("T1.4: Verify Metric Count String Formatting")
    @MainActor
    func testMetricCountFormatting() throws {
        #expect(UserProfile.formatCount(0) == "0")
        #expect(UserProfile.formatCount(950) == "950")
        #expect(UserProfile.formatCount(1_500) == "1.5K")
        #expect(UserProfile.formatCount(18_400) == "18.4K")
        #expect(UserProfile.formatCount(1_200_000) == "1.2M")
    }

    @Test("T1.5: Verify User Profile Hashable and Equatable Conformance")
    @MainActor
    func testUserProfileEqualityAndHashing() throws {
        let provider = MockDataProvider()
        let profile1 = provider.currentProfile
        let profile2 = provider.currentProfile

        #expect(profile1 == profile2)
        var hasher1 = Hasher()
        profile1.hash(into: &hasher1)
        var hasher2 = Hasher()
        profile2.hash(into: &hasher2)
        #expect(hasher1.finalize() == hasher2.finalize())
    }

    // MARK: - Tier 2: Boundary & Corner Cases

    @Test("T2.1: Verify Fetch Non-Existent User ID Throws API Error Gracefully")
    @MainActor
    func testFetchUserProfileNotFound() async throws {
        let service = MockClientService()

        await #expect(throws: XKitError.self) {
            try await service.fetchUserProfile(id: "non_existent_usr_9999")
        }
    }

    @Test("T2.2: Verify Zero Metrics and Nil Bio Fallbacks")
    @MainActor
    func testZeroMetricsAndNilBio() throws {
        let rawUser = XUser(
            id: "usr_zero_001",
            name: "Newbie",
            username: "newbie_01",
            description: nil,
            verified: false,
            profileImageUrl: nil
        )
        let profile = UserProfile(
            user: rawUser,
            headerImageUrl: nil,
            bio: nil,
            location: nil,
            websiteUrl: nil,
            joinedDate: Date(),
            followersCount: 0,
            followingCount: 0,
            postsCount: 0,
            isFollowing: false
        )

        #expect(profile.followersCount == 0)
        #expect(profile.followingCount == 0)
        #expect(profile.postsCount == 0)
        #expect(profile.bio == nil)
        #expect(profile.location == nil)
        #expect(profile.websiteUrl == nil)
        #expect(profile.isVerified == false)
    }

    @Test("T2.3: Verify Optimistic Follower Count Increment and Mutation")
    @MainActor
    func testOptimisticFollowerCountMutation() {
        let rawUser = XUser(id: "usr_target_01", name: "Target", username: "target")
        let profile = UserProfile(user: rawUser, followersCount: 100, isFollowing: false)

        let vm = ProfileViewModel(userId: "usr_target_01", initialProfile: profile)
        #expect(vm.isCurrentUser == false)
        #expect(vm.isFollowing == false)
        #expect(vm.followersCount == 100)
        #expect(vm.actionMode == .otherUser(isFollowing: false))

        // Optimistic follow toggle
        vm.toggleFollow()
        #expect(vm.isFollowing == true)
        #expect(vm.followersCount == 101)
        #expect(vm.userProfile?.followersCount == 101)
        #expect(vm.actionMode == .otherUser(isFollowing: true))

        // Optimistic unfollow toggle
        vm.toggleFollow()
        #expect(vm.isFollowing == false)
        #expect(vm.followersCount == 100)
        #expect(vm.userProfile?.followersCount == 100)
        #expect(vm.actionMode == .otherUser(isFollowing: false))
    }

    @Test("T2.4: Verify Parallax Banner Height Calculation at Negative and Positive Scroll Offsets")
    @MainActor
    func testParallaxBannerHeightCalculation() {
        let baseHeight: CGFloat = 150.0

        // Overscroll / pull down: scrollOffsetY < 0 (-50) -> stretch height: 150 - (-50) = 200
        let pullOffset: CGFloat = -50.0
        let stretchedHeight = ProfileGeometry.effectiveBannerHeight(baseHeight: baseHeight, scrollOffsetY: pullOffset)
        let stretchedOffset = ProfileGeometry.effectiveBannerOffset(scrollOffsetY: pullOffset)

        #expect(stretchedHeight == 200.0)
        #expect(stretchedOffset == -50.0)

        // Normal scroll up: scrollOffsetY > 0 (+80) -> fixed base height with half-speed parallax offset
        let scrollUpOffset: CGFloat = 80.0
        let recedeHeight = ProfileGeometry.effectiveBannerHeight(baseHeight: baseHeight, scrollOffsetY: scrollUpOffset)
        let recedeOffset = ProfileGeometry.effectiveBannerOffset(scrollOffsetY: scrollUpOffset)

        #expect(recedeHeight == 150.0)
        #expect(recedeOffset == 32.0)
    }

    @Test("T2.5: Verify Dynamic Avatar Scale Factor Clamping")
    @MainActor
    func testAvatarScaleFactorClamping() {
        #expect(ProfileGeometry.avatarScale(for: 0.0) == 1.0)
        #expect(ProfileGeometry.avatarScale(for: 45.0) == 0.5)
        #expect(ProfileGeometry.avatarScale(for: 90.0) == 0.0)
        #expect(ProfileGeometry.avatarScale(for: 150.0) == 0.0) // Clamped to 0
        #expect(ProfileGeometry.avatarScale(for: -40.0) == 1.0) // Overscroll clamped to 1.0
        #expect(ProfileGeometry.navigationBarOpacity(for: 0.0) == 0.0)
        #expect(ProfileGeometry.navigationBarOpacity(for: 100.0) == 0.5)
        #expect(ProfileGeometry.navigationBarOpacity(for: 120.0) == 1.0)
        #expect(ProfileGeometry.navigationBarOpacity(for: 200.0) == 1.0)
    }

    @Test("T2.6: Verify All Subtab Enum Cases and Empty State Descriptions")
    @MainActor
    func testSubtabEnumIntegrity() {
        #expect(ProfileSubtab.allCases.count == 4)
        let titles = ProfileSubtab.allCases.map(\.title)
        #expect(titles == ["Posts", "Replies", "Media", "Likes"])

        for subtab in ProfileSubtab.allCases {
            #expect(!subtab.emptyStateIcon.isEmpty)
            let desc = subtab.emptyDescription(for: "liquidglass")
            #expect(desc.contains("liquidglass"))
        }
    }

    // MARK: - Tier 3: Cross-Feature Pairwise Interactions

    @Test("T3.1: Profile Post Feed Direct Integration with PostCardView Data Binding")
    @MainActor
    func testProfilePostCardBinding() {
        let provider = MockDataProvider()
        let post = provider.postItems[0]

        #expect(!post.id.isEmpty)
        #expect(!post.author.name.isEmpty)
        #expect(!post.text.isEmpty)

        // Flatten into ProfileMediaItem
        if let firstAttachment = post.mediaAttachments.first {
            let mediaItem = ProfileMediaItem(attachment: firstAttachment, post: post)
            #expect(mediaItem.id == "\(post.id)_\(firstAttachment.id)")
            #expect(mediaItem.attachment.id == firstAttachment.id)
            #expect(mediaItem.post.id == post.id)
        }
    }

    @Test("T3.2: Profile Post Bookmark, Like, and Repost Synchronization Across Feeds")
    @MainActor
    func testProfileSocialMutationsSync() async {
        let provider = MockDataProvider()
        let service = MockClientService(
            currentUser: provider.currentUser,
            timelinePosts: provider.timelinePosts,
            users: provider.users
        )
        let vm = ProfileViewModel(userId: provider.currentUser.id, service: service)
        await vm.loadProfile()

        guard let targetPost = vm.currentPosts.first else {
            Issue.record("Expected currentPosts to have items")
            return
        }

        let initialLike = targetPost.isLiked
        vm.toggleLike(for: targetPost)
        let updatedPost = vm.currentPosts.first(where: { $0.id == targetPost.id })
        #expect(updatedPost?.isLiked == !initialLike)

        let initialRepost = targetPost.isReposted
        vm.toggleRepost(for: targetPost)
        let repostedPost = vm.currentPosts.first(where: { $0.id == targetPost.id })
        #expect(repostedPost?.isReposted == !initialRepost)

        let initialBookmark = targetPost.isBookmarked
        vm.toggleBookmark(for: targetPost)
        let bookmarkedPost = vm.currentPosts.first(where: { $0.id == targetPost.id })
        #expect(bookmarkedPost?.isBookmarked == !initialBookmark)
    }

    @Test("T3.3: Profile Pull-To-Refresh Cache Invalidation Lifecycle")
    @MainActor
    func testProfilePullToRefreshLifecycle() async {
        let provider = MockDataProvider()
        let service = MockClientService(
            currentUser: provider.currentUser,
            timelinePosts: provider.timelinePosts,
            users: provider.users
        )
        let vm = ProfileViewModel(userId: provider.currentUser.id, service: service)
        await vm.loadProfile()

        #expect(vm.postsBySubtab[.posts] != nil)
        #expect(vm.isRefreshing == false)

        await vm.refreshProfile()

        #expect(vm.postsBySubtab[.posts] != nil)
        #expect(vm.isRefreshing == false)
        #expect(vm.errorMessage == nil)
    }

    // MARK: - Tier 4: Real-World Application Scenario

    @Test("T4.1: Scenario 4 - User Profile Navigation & Subtab Filtering Flow")
    @MainActor
    func testScenario4_UserProfileNavigationAndSubtabFiltering() async throws {
        let provider = MockDataProvider()
        let service = MockClientService(
            currentUser: provider.currentUser,
            timelinePosts: provider.timelinePosts,
            users: provider.users
        )

        // Step 1: Initialize ViewModel for external author
        let targetAuthorId = "usr_author_002" // Swift Core Team
        let vm = ProfileViewModel(userId: targetAuthorId, service: service)
        #expect(vm.isCurrentUser == false)

        // Step 2: Load profile
        await vm.loadProfile()
        #expect(vm.userProfile != nil)
        #expect(vm.userProfile?.user.id == targetAuthorId)
        #expect(vm.userProfile?.user.username == "swift_lang")

        // Step 3: Browse posts
        #expect(vm.selectedSubtab == .posts)
        let posts = vm.currentPosts
        #expect(!posts.isEmpty)

        // Step 4: Toggle to Replies
        vm.selectSubtab(.replies)
        await vm.fetchFeedIfNeeded(for: .replies)
        #expect(vm.selectedSubtab == .replies)

        // Step 5: Toggle to Media
        vm.selectSubtab(.media)
        await vm.fetchFeedIfNeeded(for: .media)
        #expect(vm.selectedSubtab == .media)

        // Step 6: Toggle Follow
        let initialFollowing = vm.isFollowing
        let initialFollowers = vm.followersCount
        vm.toggleFollow()
        #expect(vm.isFollowing == !initialFollowing)
        #expect(vm.followersCount == initialFollowers + 1)

        // Step 7: Pull to refresh
        await vm.refreshProfile()
        #expect(vm.errorMessage == nil)
        #expect(vm.isFollowing == !initialFollowing)
        #expect(vm.followersCount == initialFollowers + 1)
        #expect(vm.userProfile?.followersCount == initialFollowers + 1)
    }
}
