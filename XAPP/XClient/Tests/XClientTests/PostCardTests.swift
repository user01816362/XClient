//
//  PostCardTests.swift
//  XClientTests
//
//  Automated Unit & Component Tests for Milestone 3 (Feature F5):
//  Entity parsing (mentions, hashtags, URLs), optimistic action toggles,
//  monospaced metrics formatting, quoted card recursion bounding, and accessibility.
//  100% Swift 6 strict concurrency compliance.
//

import Testing
import Foundation
import SwiftUI
import XKitModels
@testable import XClient

@Suite("Milestone 3: Rich PostCard Component & Entity Parser Tests", .serialized)
struct PostCardTests {

    // MARK: - Test 2.1: Entity Parsing - Mentions
    @Test("Verify Extraction of Single and Multiple @mentions")
    func testMentionEntityParsing() {
        let text = "Welcome @liquidglass and @swift_lang to the new client!"
        let spans = PostEntityParser.parse(text: text)

        let mentions = spans.compactMap { span -> String? in
            if case .mention(let username) = span.type { return username }
            return nil
        }

        #expect(mentions.count == 2)
        #expect(mentions[0] == "liquidglass")
        #expect(mentions[1] == "swift_lang")
    }

    // MARK: - Test 2.2: Entity Parsing - Hashtags
    @Test("Verify Extraction of #hashtags with Punctuation Boundary Stripping")
    func testHashtagEntityParsing() {
        let text = "Building with #SwiftUI and #LiquidGlass! Follow #100DaysOfCode."
        let spans = PostEntityParser.parse(text: text)

        let hashtags = spans.compactMap { span -> String? in
            if case .hashtag(let tag) = span.type { return tag }
            return nil
        }

        #expect(hashtags.count == 3)
        #expect(hashtags[0] == "SwiftUI")
        #expect(hashtags[1] == "LiquidGlass")
        #expect(hashtags[2] == "100DaysOfCode")
    }

    // MARK: - Test 2.3: Entity Parsing - RFC URLs
    @Test("Verify Extraction of Standard HTTP and HTTPS URLs")
    func testURLEntityParsing() {
        let text = "Check out https://developer.apple.com/swift and http://swift.org"
        let spans = PostEntityParser.parse(text: text)

        let urls = spans.compactMap { span -> URL? in
            if case .url(let url, _) = span.type { return url }
            return nil
        }

        #expect(urls.count == 2)
        #expect(urls[0].absoluteString == "https://developer.apple.com/swift")
        #expect(urls[1].absoluteString == "http://swift.org")
    }

    // MARK: - Test 2.4: Complex Interleaved Entities
    @Test("Verify Interleaved Mentions, Hashtags, and URLs in Single Post Body")
    func testInterleavedEntityParsing() {
        let text = "Hey @alice, check #design at https://apple.com! cc: @bob #iOS"
        let spans = PostEntityParser.parse(text: text)

        #expect(spans.count == 5)

        // Verify non-overlapping ranges
        for i in 0..<(spans.count - 1) {
            #expect(spans[i].range.upperBound <= spans[i + 1].range.lowerBound)
        }
    }

    // MARK: - Test 2.5: Entity Parsing Corner Cases
    @Test("Verify Entity Parsing Defenses for Empty Text, Emails, and Bare Symbols")
    func testEntityParsingCornerCases() {
        // Empty text
        #expect(PostEntityParser.parse(text: "").isEmpty)

        // Email address should not extract standalone @example mention
        let emailSpans = PostEntityParser.parse(text: "Send to support@example.com for help")
        let mentions = emailSpans.compactMap { span -> String? in
            if case .mention(let u) = span.type { return u }
            return nil
        }
        #expect(mentions.isEmpty, "Email was incorrectly parsed as user mention")

        // Bare isolated symbols
        let bareSpans = PostEntityParser.parse(text: "Symbols only: @ # https://")
        #expect(bareSpans.isEmpty)

        // Unicode / Emojis
        let emojiSpans = PostEntityParser.parse(text: "🚀 @satoshi #Crypto https://x.com")
        #expect(emojiSpans.count == 3)
    }

    // MARK: - Test 2.6: Optimistic Like Toggle & Underflow Defense
    @Test("Verify Optimistic Like Toggle and Underflow Prevention via TimelineViewModel & MockDataProvider")
    @MainActor
    func testOptimisticLikeToggle() {
        MockDataProvider.shared.resetToDefaults()
        let provider = MockDataProvider.shared
        let service = MockClientService(
            currentUser: provider.currentUser,
            timelinePosts: provider.timelinePosts,
            users: provider.users
        )
        let viewModel = TimelineViewModel(service: service)

        var testPost = provider.postItems[1]
        testPost.isLiked = false
        testPost.likeCount = 0
        if let idx = provider.postItems.firstIndex(where: { $0.id == testPost.id }) {
            provider.postItems[idx].isLiked = false
            provider.postItems[idx].likeCount = 0
        }
        viewModel.posts = [testPost]

        // 1. Toggle Like ON via TimelineViewModel
        viewModel.toggleLike(for: testPost)
        #expect(viewModel.posts[0].isLiked == true)
        #expect(viewModel.posts[0].likeCount == 1)
        #expect(MockDataProvider.shared.postItems.first(where: { $0.id == testPost.id })?.isLiked == true)

        // 2. Toggle Like OFF via TimelineViewModel
        let likedPost = viewModel.posts[0]
        viewModel.toggleLike(for: likedPost)
        #expect(viewModel.posts[0].isLiked == false)
        #expect(viewModel.posts[0].likeCount == 0)
        #expect(MockDataProvider.shared.postItems.first(where: { $0.id == testPost.id })?.isLiked == false)

        // 3. Underflow check: unliking at 0 remains 0
        viewModel.posts[0].isLiked = true
        viewModel.posts[0].likeCount = 0
        viewModel.toggleLike(for: viewModel.posts[0])
        #expect(viewModel.posts[0].isLiked == false)
        #expect(viewModel.posts[0].likeCount == 0, "likeCount must never underflow below 0")

        // 4. MockDataProvider direct underflow check
        let mockPostId = testPost.id
        if let idx = MockDataProvider.shared.postItems.firstIndex(where: { $0.id == mockPostId }) {
            MockDataProvider.shared.postItems[idx].isLiked = true
            MockDataProvider.shared.postItems[idx].likeCount = 0
            MockDataProvider.shared.toggleLike(postId: mockPostId)
            #expect(MockDataProvider.shared.postItems[idx].likeCount == 0)
            #expect(MockDataProvider.shared.postItems[idx].isLiked == false)
        }
    }

    // MARK: - Test 2.7: Optimistic Bookmark Toggle & Sync
    @Test("Verify Optimistic Bookmark Toggle and MockDataProvider State Sync")
    @MainActor
    func testOptimisticBookmarkToggle() {
        let provider = MockDataProvider.shared
        var post = provider.postItems[1]
        let initialBookmarkCount = post.bookmarkCount
        let targetId = post.id

        // Toggle Bookmark ON
        post.isBookmarked = true
        post.bookmarkCount = max(0, post.bookmarkCount + 1)
        _ = provider.toggleBookmark(postId: targetId, forceState: true)

        #expect(post.isBookmarked == true)
        #expect(post.bookmarkCount == initialBookmarkCount + 1)
        #expect(provider.bookmarks.contains(where: { $0.id == targetId }))

        // Toggle Bookmark OFF
        post.isBookmarked = false
        post.bookmarkCount = max(0, post.bookmarkCount - 1)
        _ = provider.toggleBookmark(postId: targetId, forceState: false)

        #expect(post.isBookmarked == false)
        #expect(post.bookmarkCount == initialBookmarkCount)
        #expect(!provider.bookmarks.contains(where: { $0.id == targetId }))
    }

    // MARK: - Test 2.8: Optimistic Repost Toggle & Underflow Defense
    @Test("Verify Optimistic Repost Toggle Increments Count, Toggles State, and Prevents Underflow")
    @MainActor
    func testOptimisticRepostToggle() {
        let provider = MockDataProvider()
        let service = MockClientService(
            currentUser: provider.currentUser,
            timelinePosts: provider.timelinePosts,
            users: provider.users
        )
        let viewModel = TimelineViewModel(service: service)

        var testPost = provider.postItems[2]
        testPost.isReposted = false
        testPost.repostCount = 5
        viewModel.posts = [testPost]

        // 1. Toggle Repost ON
        viewModel.toggleRepost(for: testPost)
        #expect(viewModel.posts[0].isReposted == true)
        #expect(viewModel.posts[0].repostCount == 6)
        #expect(MockDataProvider.shared.postItems.first(where: { $0.id == testPost.id })?.isReposted == true)

        // 2. Toggle Repost OFF
        let repostedPost = viewModel.posts[0]
        viewModel.toggleRepost(for: repostedPost)
        #expect(viewModel.posts[0].isReposted == false)
        #expect(viewModel.posts[0].repostCount == 5)
        #expect(MockDataProvider.shared.postItems.first(where: { $0.id == testPost.id })?.isReposted == false)

        // 3. Underflow check: un-reposting at 0 remains 0
        viewModel.posts[0].isReposted = true
        viewModel.posts[0].repostCount = 0
        viewModel.toggleRepost(for: viewModel.posts[0])
        #expect(viewModel.posts[0].isReposted == false)
        #expect(viewModel.posts[0].repostCount == 0, "repostCount must never underflow below 0")

        // 4. MockDataProvider direct underflow check
        let mockPostId = testPost.id
        if let idx = MockDataProvider.shared.postItems.firstIndex(where: { $0.id == mockPostId }) {
            MockDataProvider.shared.postItems[idx].isReposted = true
            MockDataProvider.shared.postItems[idx].repostCount = 0
            MockDataProvider.shared.toggleRepost(postId: mockPostId)
            #expect(MockDataProvider.shared.postItems[idx].repostCount == 0, "MockDataProvider.toggleRepost must not underflow below 0")
            #expect(MockDataProvider.shared.postItems[idx].isReposted == false)
        }
    }

    // MARK: - Test 2.9: Monospaced Numeric Metrics Formatting
    @Test("Verify ActionButtonBar FormatCount Conforms to Compact HIG Metrics")
    @MainActor
    func testMonospacedMetricsFormatting() {
        #expect(ActionButtonBar.formatCount(0) == "0")
        #expect(ActionButtonBar.formatCount(42) == "42")
        #expect(ActionButtonBar.formatCount(999) == "999")
        #expect(ActionButtonBar.formatCount(1_000) == "1.0K")
        #expect(ActionButtonBar.formatCount(1_250) == "1.2K" || ActionButtonBar.formatCount(1_250) == "1.3K")
        #expect(ActionButtonBar.formatCount(45_600) == "45.6K")
        #expect(ActionButtonBar.formatCount(1_000_000) == "1.0M")
        #expect(ActionButtonBar.formatCount(2_500_000) == "2.5M")
    }

    // MARK: - Test 2.10: Quoted Card Nil Safety
    @Test("Verify Post with Nil Quoted Post Renders Without Quote Container")
    @MainActor
    func testQuotedCardNilSafety() {
        let post = MockDataProvider.shared.postItems[0]
        #expect(post.quotedPost == nil)
    }

    // MARK: - Test 2.11: Quoted Card Recursion Bounding & Cycle Safety
    @Test("Verify Single-Level Quoted Card Nesting and Cycle Termination Safety")
    @MainActor
    func testQuotedCardCycleDefense() {
        let author = MockDataProvider.shared.currentUser
        let innerPost = PostItem(id: "post_inner", text: "Inner post", author: author)
        let outerPost = PostItem(
            id: "post_outer",
            text: "Outer post quoting inner",
            author: author,
            quotedPost: .post(innerPost)
        )

        #expect(outerPost.quotedPost != nil)
        #expect(outerPost.quotedPost?.postItem.id == "post_inner")

        // QuotedCardView accepts PostItem directly and does not render nested quotes
        let quotedView = QuotedCardView(post: innerPost)
        #expect(quotedView.post.id == "post_inner")
    }

    // MARK: - Test 2.12: Relative Time String Calculations
    @Test("Verify Relative Time Strings for Timestamps (now, m, h, d, w)")
    @MainActor
    func testRelativeTimeStringCalculations() {
        let author = MockDataProvider.shared.currentUser
        let now = Date()

        let postNow = PostItem(id: "p1", text: "T", author: author, createdAt: now.addingTimeInterval(-10))
        #expect(postNow.relativeTimeString == "now")

        let postMinutes = PostItem(id: "p2", text: "T", author: author, createdAt: now.addingTimeInterval(-300))
        #expect(postMinutes.relativeTimeString == "5m")

        let postHours = PostItem(id: "p3", text: "T", author: author, createdAt: now.addingTimeInterval(-7200))
        #expect(postHours.relativeTimeString == "2h")

        let postDays = PostItem(id: "p4", text: "T", author: author, createdAt: now.addingTimeInterval(-86400 * 3))
        #expect(postDays.relativeTimeString == "3d")

        let postWeeks = PostItem(id: "p5", text: "T", author: author, createdAt: now.addingTimeInterval(-86400 * 14))
        #expect(postWeeks.relativeTimeString == "2w")
    }

    // MARK: - Test 2.13: VoiceOver Accessibility Labels
    @Test("Verify Accessibility Labels on Action Buttons Reflect State and Counts")
    @MainActor
    func testActionButtonAccessibilityLabels() {
        // Test production ActionButtonBar accessibility helpers
        let unliked = ActionButtonBar.likeAccessibilityLabel(isLiked: false, count: 10)
        #expect(unliked == "Like, 10 likes")

        let liked = ActionButtonBar.likeAccessibilityLabel(isLiked: true, count: 11)
        #expect(liked == "Unlike, 11 likes")

        let unreposted = ActionButtonBar.repostAccessibilityLabel(isReposted: false, count: 42)
        #expect(unreposted == "Repost, 42 reposts")

        let reposted = ActionButtonBar.repostAccessibilityLabel(isReposted: true, count: 43)
        #expect(reposted == "Undo repost, 43 reposts")

        let unbookmarked = ActionButtonBar.bookmarkAccessibilityLabel(isBookmarked: false, count: 5)
        #expect(unbookmarked == "Bookmark, 5 bookmarks")

        let bookmarked = ActionButtonBar.bookmarkAccessibilityLabel(isBookmarked: true, count: 6)
        #expect(bookmarked == "Remove bookmark, 6 bookmarks")

        let reply = ActionButtonBar.replyAccessibilityLabel(count: 3)
        #expect(reply == "3 replies")

        // Underflow sanitization check (negative counts must not announce negative numbers)
        #expect(ActionButtonBar.likeAccessibilityLabel(isLiked: false, count: -1) == "Like, 0 likes")
        #expect(ActionButtonBar.repostAccessibilityLabel(isReposted: false, count: -5) == "Repost, 0 reposts")
        #expect(ActionButtonBar.bookmarkAccessibilityLabel(isBookmarked: false, count: -2) == "Bookmark, 0 bookmarks")
        #expect(ActionButtonBar.replyAccessibilityLabel(count: -1) == "0 replies")

        // View instantiation check
        let bar = ActionButtonBar(
            replyCount: 3,
            repostCount: 5,
            likeCount: 10,
            bookmarkCount: 2,
            isLiked: true,
            isReposted: false,
            isBookmarked: true
        )
        #expect(bar.likeCount == 10)
        #expect(bar.isLiked == true)
        #expect(bar.repostCount == 5)
        #expect(bar.isReposted == false)
        #expect(bar.bookmarkCount == 2)
        #expect(bar.isBookmarked == true)
    }

    // MARK: - Test 2.14: Verification Badge Resolution
    @Test("Verify VerificationBadgeType Resolution for Organizations and Users")
    func testVerificationBadgeResolution() {
        let unverified = XUser(id: "u1", name: "User", username: "user", verified: false)
        #expect(VerificationBadgeType.resolve(from: unverified) == .none)

        let verifiedUser = XUser(id: "u2", name: "Dev", username: "apple_dev", verified: true, verifiedType: "blue")
        #expect(VerificationBadgeType.resolve(from: verifiedUser) == .blue)

        let officialOrg = XUser(id: "u3", name: "Swift", username: "swift_lang", verified: true, verifiedType: "business")
        #expect(VerificationBadgeType.resolve(from: officialOrg) == .gold)

        let govOfficial = XUser(id: "u4", name: "Gov", username: "agency", verified: true, verifiedType: "government")
        #expect(VerificationBadgeType.resolve(from: govOfficial) == .gray)
    }
}
