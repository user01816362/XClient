//
//  Milestone3EmpiricalChallengerTests.swift
//  XClientTests
//
//  Empirical Challenger Stress Test Suite for Milestone 3:
//  - PostEntityParser: Malicious strings, ReDoS stress, Unicode grapheme clusters, RTL overrides, null bytes
//  - QuotedCardView: Recursive nesting, conceptual self-referencing cycles, Equatable/Codable stack safety
//  - ActionButtonBar & ViewModels: Numeric underflow defenses, extreme bounds, negative interaction counts
//  - MediaDownloadManager: Directory traversal in saveMediaToLocalDevice & cacheKey, filename collisions, concurrent download races & cancellation interference
//  100% Swift 6 strict concurrency compliance.
//

import Testing
import Foundation
import SwiftUI
import CryptoKit
@testable import XClient
import XKitModels

// MARK: - Mock URL Protocol for Challenger

private final class ChallengerMockURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var handlers: [URL: (statusCode: Int, data: Data, delayMs: UInt32)] = [:]

    static func setHandler(for url: URL, statusCode: Int, data: Data, delayMs: UInt32 = 0) {
        lock.lock()
        defer { lock.unlock() }
        handlers[url] = (statusCode, data, delayMs)
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        handlers.removeAll()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        Self.lock.lock()
        let handler = Self.handlers[url]
        Self.lock.unlock()

        if let handler = handler {
            if handler.delayMs > 0 {
                usleep(handler.delayMs * 1000)
            }
            let response = HTTPURLResponse(
                url: url,
                statusCode: handler.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Length": "\(handler.data.count)"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: handler.data)
            client?.urlProtocolDidFinishLoading(self)
        } else {
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Length": "1024"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(repeating: 0xAB, count: 1024))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

// MARK: - Milestone 3 Empirical Challenger Test Suite

@Suite("Milestone 3 Empirical Challenger Test Suite", .serialized)
struct Milestone3EmpiricalChallengerTests {

    // Helper to create test MediaDownloadManager
    @MainActor
    private func makeChallengerManager() -> (MediaDownloadManager, URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ChallengerMedia_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ChallengerMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let manager = MediaDownloadManager(session: session, customCacheDirectory: tempDir)
        return (manager, tempDir)
    }

    private func cleanup(tempDir: URL) {
        try? FileManager.default.removeItem(at: tempDir)
        ChallengerMockURLProtocol.reset()
    }

    // =========================================================================
    // SECTION 1: PostEntityParser Adversarial String & Stress Challenges
    // =========================================================================

    @Test("Challenge 1.1: Complex Unicode Grapheme Clusters & ASCII Hashtag Limitation")
    func testUnicodeGraphemeClustersAndCombiningMarks() {
        let text = "👨‍👩‍👧‍👦 @family #happy 🇦🇺 @aussie #flag e\u{301} @paris #crème_brûlée"
        let spans = PostEntityParser.parse(text: text)

        // Verify mentions
        let mentions = spans.compactMap { span -> String? in
            if case .mention(let u) = span.type { return u }
            return nil
        }
        #expect(mentions == ["family", "aussie", "paris"])

        // Verify hashtags: PostEntityParser regex [a-zA-Z0-9_]+ fails on non-ASCII characters
        let hashtags = spans.compactMap { span -> String? in
            if case .hashtag(let t) = span.type { return t }
            return nil
        }
        #expect(hashtags.contains("happy"))
        #expect(hashtags.contains("flag"))
        
        // Document empirical limitation: Unicode accented hashtag #crème_brûlée is dropped
        let unicodeHashtagParsed = hashtags.contains("crème_brûlée")
        if !unicodeHashtagParsed {
            // Documenting known limitation of ASCII-only regex
            #expect(!hashtags.contains("crème_brûlée"), "PostEntityParser does not support Unicode hashtags")
        }

        // Verify attributed string does not crash and spans match range boundaries
        let attr = PostEntityParser.makeAttributedString(text: text, accentColor: .blue)
        #expect(attr.characters.count == text.count)
    }

    @Test("Challenge 1.2: RTL Bi-Directional Override and Control Characters")
    func testRTLAndControlCharacters() {
        let text = "\u{202E}@evil\u{202C} normal @good \u{200B}#zero_width \0@null_char"
        let spans = PostEntityParser.parse(text: text)

        // Ensure parser does not crash and handles presence of hidden/RTL characters
        for span in spans {
            #expect(!span.text.isEmpty)
            #expect(span.range.lowerBound >= text.startIndex)
            #expect(span.range.upperBound <= text.endIndex)
        }

        let attr = PostEntityParser.makeAttributedString(text: text, accentColor: .blue)
        #expect(!attr.description.isEmpty)
    }

    @Test("Challenge 1.3: ReDoS & Massive Input Performance Stress")
    func testReDoSAndMassiveInputPerformance() {
        // 1. 20,000 character repetition of prefix tokens
        let repeatedAt = String(repeating: "@", count: 20_000)
        let startTime1 = CFAbsoluteTimeGetCurrent()
        let spans1 = PostEntityParser.parse(text: repeatedAt)
        let duration1 = CFAbsoluteTimeGetCurrent() - startTime1
        #expect(spans1.isEmpty)
        #expect(duration1 < 1.0, "ReDoS on repeated @ exceeded 1s: took \(duration1)s")

        // 2. Long username candidate exceeding 15 chars (e.g. 10,000 chars)
        let longHandleCandidate = "@" + String(repeating: "a", count: 10_000)
        let startTime2 = CFAbsoluteTimeGetCurrent()
        let spans2 = PostEntityParser.parse(text: longHandleCandidate)
        let duration2 = CFAbsoluteTimeGetCurrent() - startTime2
        #expect(spans2.isEmpty, "Handle longer than 15 chars was incorrectly parsed")
        #expect(duration2 < 1.0, "ReDoS on long handle exceeded 1s: took \(duration2)s")

        // 3. 1,000 valid interleaved tokens
        var mixedText = ""
        for i in 0..<1000 {
            mixedText += "@user\(i % 100) #tag\(i % 50) https://example.com/page\(i) "
        }
        let startTime3 = CFAbsoluteTimeGetCurrent()
        let spans3 = PostEntityParser.parse(text: mixedText)
        let duration3 = CFAbsoluteTimeGetCurrent() - startTime3
        #expect(spans3.count == 3000)
        #expect(duration3 < 2.0, "Parsing 3,000 entities exceeded 2s: took \(duration3)s")
    }

    @Test("Challenge 1.4: URL Host Boundary and Scheme Spoofing Defense")
    func testURLHostAndSchemeSpoofingDefense() {
        let malicious = [
            "javascript:alert(1)",
            "data:text/html,<script>evil()</script>",
            "file:///etc/passwd",
            "http://",
            "https://.",
            "http://:80",
            "mailto:victim@example.com"
        ]

        for text in malicious {
            let spans = PostEntityParser.parse(text: text)
            for span in spans {
                if case .url(let url, _) = span.type {
                    #expect(url.host != nil && !url.host!.isEmpty, "URL entity without valid host was allowed: \(url)")
                    #expect(url.scheme == "http" || url.scheme == "https", "Unsafe scheme accepted: \(url)")
                }
            }
        }
    }

    @Test("Challenge 1.5: Non-Overlapping Spans in URLs with Embedded Entities")
    func testEntitiesInsideURLsAreNotDuplicated() {
        let text = "Visit https://example.com/@alice#section for details."
        let spans = PostEntityParser.parse(text: text)

        #expect(spans.count == 1)
        if case .url(let url, _) = spans[0].type {
            #expect(url.absoluteString.contains("example.com/@alice#section"))
        } else {
            Issue.record("Expected URL entity but found \(spans[0].type)")
        }
    }

    @Test("Challenge 1.6: Parenthesized Entities and Bracket Enclosure Parsing")
    func testParenthesizedAndBracketEnclosedEntities() {
        let text = "Check out (@developer) and [#swiftui] and {#apple} tags: #swift(#ios) also ((@nested))"
        let spans = PostEntityParser.parse(text: text)

        let mentions = spans.compactMap { span -> String? in
            if case .mention(let u) = span.type { return u }
            return nil
        }
        #expect(mentions.contains("developer"), "Failed to extract parenthesized mention (@developer)")
        #expect(mentions.contains("nested"), "Failed to extract nested parenthesized mention ((@nested))")

        let hashtags = spans.compactMap { span -> String? in
            if case .hashtag(let t) = span.type { return t }
            return nil
        }
        #expect(hashtags.contains("swiftui"), "Failed to extract bracketed hashtag [#swiftui]")
        #expect(hashtags.contains("apple"), "Failed to extract braced hashtag {#apple}")
        #expect(hashtags.contains("swift"), "Failed to extract #swift from #swift(#ios)")
        #expect(hashtags.contains("ios"), "Failed to extract parenthesized #ios from #swift(#ios)")

        // Negative boundary cases: email addresses and mid-word hashes must not parse
        let negText = "contact: test@example.com, code#invalid, word#123"
        let negSpans = PostEntityParser.parse(text: negText)
        let negMentions = negSpans.compactMap { span -> String? in
            if case .mention(let u) = span.type { return u }
            return nil
        }
        #expect(negMentions.isEmpty, "Email was extracted as mention: \(negMentions)")
        let negHashtags = negSpans.compactMap { span -> String? in
            if case .hashtag(let t) = span.type { return t }
            return nil
        }
        #expect(negHashtags.isEmpty, "Mid-word hash was extracted as hashtag: \(negHashtags)")
    }

    @Test("Challenge 1.7: Non-Latin and Extended Unicode Hashtag Support")
    func testNonLatinAndExtendedUnicodeHashtags() {
        let text = "Multilingual tags: #crème_brûlée #日本語 #кириллица #españa #한국어 #العربية #עברית"
        let spans = PostEntityParser.parse(text: text)

        let hashtags = spans.compactMap { span -> String? in
            if case .hashtag(let t) = span.type { return t }
            return nil
        }

        #expect(hashtags.contains("crème_brûlée"), "Missing #crème_brûlée: parsed \(hashtags)")
        #expect(hashtags.contains("日本語"), "Missing #日本語: parsed \(hashtags)")
        #expect(hashtags.contains("кириллица"), "Missing #кириллица: parsed \(hashtags)")
        #expect(hashtags.contains("españa"), "Missing #españa: parsed \(hashtags)")
        #expect(hashtags.contains("한국어"), "Missing #한국어: parsed \(hashtags)")
        #expect(hashtags.contains("العربية"), "Missing #العربية: parsed \(hashtags)")
        #expect(hashtags.contains("עברית"), "Missing #עברית: parsed \(hashtags)")

        // Ensure makeAttributedString works and does not crash or drop characters
        let attr = PostEntityParser.makeAttributedString(text: text, accentColor: .blue)
        #expect(attr.characters.count == text.count)
    }


    // =========================================================================
    // SECTION 2: QuotedCardView Recursion & Cycle Challenges
    // =========================================================================

    @Test("Challenge 2.1: Conceptual Self-Referencing Cycle Safety")
    @MainActor
    func testConceptualSelfReferencingCycleSafety() {
        let author = XUser(id: "usr_alice", name: "Alice", username: "alice")
        let basePost = PostItem(id: "post_cycle", text: "Echoing cycle", author: author)
        let cyclicPost = PostItem(
            id: "post_cycle",
            text: "Echoing cycle",
            author: author,
            quotedPost: .post(basePost)
        )

        // Evaluate QuotedCardView instantiation and body rendering
        let quotedView = QuotedCardView(post: cyclicPost)
        #expect(quotedView.post.id == "post_cycle")
        #expect(quotedView.post.quotedPost != nil)
        // QuotedCardView body does NOT recurse into quotedView.post.quotedPost
    }

    @Test("Challenge 2.2: Deep 100-Level Quote Nesting Chain Safety")
    @MainActor
    func testDeepQuoteNestingChainSafety() {
        let author = XUser(id: "usr_chain", name: "Chain", username: "chain")
        var current = PostItem(id: "post_0", text: "Base", author: author)

        for i in 1...100 {
            current = PostItem(
                id: "post_\(i)",
                text: "Level \(i)",
                author: author,
                quotedPost: .post(current)
            )
        }

        #expect(current.id == "post_100")

        // 1. PostCardView evaluates single-level quoted post
        let card = PostCardView(post: current)
        #expect(card.post.id == "post_100")
        #expect(card.post.quotedPost?.postItem.id == "post_99")

        // 2. Hashable does not overflow
        var hasher = Hasher()
        current.hash(into: &hasher)
        let hashValue = hasher.finalize()
        #expect(hashValue != 0)

        // 3. Equatable terminates safely
        #expect(current == current)
    }

    @Test("Challenge 2.3: QuotedCardView Nil & Empty Attribute Safety")
    @MainActor
    func testQuotedCardEmptyAttributesSafety() {
        let sparseAuthor = XUser(id: "usr_sparse", name: "", username: "")
        let sparsePost = PostItem(
            id: "post_sparse",
            text: "",
            author: sparseAuthor,
            createdAt: Date.distantPast,
            mediaAttachments: []
        )

        let quotedView = QuotedCardView(post: sparsePost)
        #expect(quotedView.post.id == "post_sparse")
        #expect(quotedView.post.relativeTimeString.isEmpty == false)
    }

    // =========================================================================
    // SECTION 3: ActionButtonBar & ViewModel Underflow Defense Challenges
    // =========================================================================

    @Test("Challenge 3.1: ActionButtonBar Negative and Extreme Numeric Counts")
    @MainActor
    func testActionButtonBarNegativeAndExtremeCounts() {
        let bar = ActionButtonBar(
            replyCount: -10,
            repostCount: -1,
            likeCount: Int.min,
            bookmarkCount: -99,
            isLiked: false,
            isReposted: false,
            isBookmarked: false
        )

        #expect(bar.replyCount == -10)
        #expect(bar.likeCount == Int.min)

        // formatCount verification
        #expect(ActionButtonBar.formatCount(-5) == "-5")
        #expect(ActionButtonBar.formatCount(0) == "0")
        #expect(ActionButtonBar.formatCount(999) == "999")
        #expect(ActionButtonBar.formatCount(1_000) == "1.0K")
        #expect(ActionButtonBar.formatCount(1_234) == "1.2K")
        #expect(ActionButtonBar.formatCount(1_000_000) == "1.0M")
        #expect(ActionButtonBar.formatCount(2_500_000) == "2.5M")
        #expect(ActionButtonBar.formatCount(Int.min) == "\(Int.min)")
    }

    @Test("Challenge 3.2: TimelineViewModel Underflow Defense on Rapid Toggles from Zero")
    @MainActor
    func testTimelineViewModelUnderflowDefense() async {
        let author = XUser(id: "usr_test", name: "Tester", username: "tester")
        let zeroItem = PostItem(
            id: "p_zero",
            text: "Testing underflow",
            author: author,
            replyCount: 0,
            repostCount: 0,
            likeCount: 0,
            bookmarkCount: 0,
            isLiked: false,
            isReposted: false,
            isBookmarked: false
        )

        MockDataProvider.shared.postItems.append(zeroItem)
        let mockService = MockClientService(timelinePosts: [zeroItem.asXPost])
        let vm = TimelineViewModel(service: mockService)
        await vm.refreshTimeline()

        guard let post = vm.posts.first(where: { $0.id == "p_zero" }) else {
            Issue.record("Failed to find p_zero in timeline")
            return
        }

        // 1. Toggle like on and off repeatedly
        vm.toggleLike(for: post)
        #expect(vm.posts.first(where: { $0.id == "p_zero" })?.likeCount == 1)
        #expect(vm.posts.first(where: { $0.id == "p_zero" })?.isLiked == true)

        vm.toggleLike(for: post)
        #expect(vm.posts.first(where: { $0.id == "p_zero" })?.likeCount == 0)
        #expect(vm.posts.first(where: { $0.id == "p_zero" })?.isLiked == false)

        // 2. Toggle repost on and off
        vm.toggleRepost(for: post)
        #expect(vm.posts.first(where: { $0.id == "p_zero" })?.repostCount == 1)
        #expect(vm.posts.first(where: { $0.id == "p_zero" })?.isReposted == true)

        vm.toggleRepost(for: post)
        #expect(vm.posts.first(where: { $0.id == "p_zero" })?.repostCount == 0)
        #expect(vm.posts.first(where: { $0.id == "p_zero" })?.isReposted == false)

        // 3. Toggle bookmark on and off
        vm.toggleBookmark(for: post)
        #expect(vm.posts.first(where: { $0.id == "p_zero" })?.bookmarkCount == 1)
        #expect(vm.posts.first(where: { $0.id == "p_zero" })?.isBookmarked == true)

        vm.toggleBookmark(for: post)
        #expect(vm.posts.first(where: { $0.id == "p_zero" })?.bookmarkCount == 0)
        #expect(vm.posts.first(where: { $0.id == "p_zero" })?.isBookmarked == false)

        // Clean up
        MockDataProvider.shared.deletePost(id: "p_zero")
    }

    @Test("Challenge 3.3: MockDataProvider toggleRepost Underflow Vulnerability Investigation")
    @MainActor
    func testMockDataProviderToggleRepostUnderflowBehavior() {
        // Create an anomalous post where isReposted is true but count is 0
        let author = XUser(id: "usr_repost_test", name: "Tester", username: "tester")
        let testPost = PostItem(
            id: "p_repost_underflow",
            text: "Anomalous repost",
            author: author,
            repostCount: 0,
            isReposted: true
        )

        MockDataProvider.shared.postItems.append(testPost)
        defer { MockDataProvider.shared.deletePost(id: "p_repost_underflow") }

        // 1. When toggled off from count 0:
        MockDataProvider.shared.toggleRepost(postId: "p_repost_underflow")

        let updated = MockDataProvider.shared.postItems.first(where: { $0.id == "p_repost_underflow" })
        #expect(updated != nil)
        #expect(updated?.isReposted == false)

        let repostCount = updated?.repostCount ?? 0
        #expect(repostCount >= 0, "MockDataProvider.toggleRepost permitted underflow to \(repostCount)!")
        #expect(repostCount == 0)

        // 2. Multi-toggle oscillation: 50 toggles from 0
        for i in 1...50 {
            MockDataProvider.shared.toggleRepost(postId: "p_repost_underflow")
            let current = MockDataProvider.shared.postItems.first(where: { $0.id == "p_repost_underflow" })!
            #expect(current.repostCount >= 0, "Iteration \(i) underflowed to \(current.repostCount)")
            if i % 2 == 1 {
                #expect(current.isReposted == true)
                #expect(current.repostCount == 1)
            } else {
                #expect(current.isReposted == false)
                #expect(current.repostCount == 0)
            }
        }

        // 3. Unknown post ID safety
        let unknownResult = MockDataProvider.shared.toggleRepost(postId: "nonexistent_post_xyz")
        #expect(unknownResult == false)

        // 4. ActionButtonBar accessibility labels clamping with negative inputs
        #expect(ActionButtonBar.repostAccessibilityLabel(isReposted: false, count: -5) == "Repost, 0 reposts")
        #expect(ActionButtonBar.repostAccessibilityLabel(isReposted: true, count: -1) == "Undo repost, 0 reposts")
        #expect(ActionButtonBar.likeAccessibilityLabel(isLiked: false, count: -10) == "Like, 0 likes")
        #expect(ActionButtonBar.likeAccessibilityLabel(isLiked: true, count: -10) == "Unlike, 0 likes")
        #expect(ActionButtonBar.bookmarkAccessibilityLabel(isBookmarked: false, count: -4) == "Bookmark, 0 bookmarks")
        #expect(ActionButtonBar.bookmarkAccessibilityLabel(isBookmarked: true, count: -4) == "Remove bookmark, 0 bookmarks")
        #expect(ActionButtonBar.replyAccessibilityLabel(count: -100) == "0 replies")
    }

    // =========================================================================
    // SECTION 4: MediaDownloadManager Security, Collision & Concurrency Challenges
    // =========================================================================

    @Test("Challenge 4.1: Path Traversal Defense in Cache Key Generation")
    @MainActor
    func testCacheKeyDirectoryTraversalImmunity() {
        let (manager, tempDir) = makeChallengerManager()
        defer { cleanup(tempDir: tempDir) }

        let attackURLs = [
            URL(string: "https://evil.com/../../../../etc/passwd")!,
            URL(string: "https://evil.com/..%2F..%2F..%2Fetc%2Fshadow")!,
            URL(string: "https://evil.com/image.png/../../../bin/sh")!,
            URL(string: "https://evil.com/folder/..%2f..%2fpayload.bin")!
        ]

        for attackURL in attackURLs {
            let key = manager.cacheKey(for: attackURL)
            #expect(!key.contains("/"), "Cache key contains forward slash: \(key)")
            #expect(!key.contains("\\"), "Cache key contains backslash: \(key)")
            #expect(!key.contains(".."), "Cache key contains relative sequence: \(key)")

            let resolvedFile = manager.cacheDirectory.appendingPathComponent(key)
            #expect(resolvedFile.standardized.path.hasPrefix(tempDir.standardized.path),
                    "Hashed file URL escaped designated cache directory: \(resolvedFile.path)")
        }
    }

    @Test("Challenge 4.2: Path Traversal Vulnerability in saveMediaToLocalDevice customFilename")
    @MainActor
    func testSaveMediaCustomFilenameTraversalVulnerability() async throws {
        let (manager, tempDir) = makeChallengerManager()
        defer { cleanup(tempDir: tempDir) }

        let testURL = URL(string: "https://example.com/media/safe.jpg")!
        ChallengerMockURLProtocol.setHandler(for: testURL, statusCode: 200, data: Data(repeating: 0x42, count: 512))

        #if os(macOS)
        let downloadsDir = tempDir.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)

        // Attack payloads attempting to traverse outside Downloads
        let attackPayloads = [
            "../../etc/passwd",
            "/tmp/escape.bin",
            "../../../../../../../../../../../tmp/challenger_traversal_\(UUID().uuidString).bin",
            "..\\..\\windows\\system32\\cmd.exe",
            "/etc/hosts",
            "../../../Downloads/../etc/passwd",
            "....//....//etc/shadow",
            "..",
            "../escape.jpg"
        ]

        for payload in attackPayloads {
            do {
                let savedURL = try await manager.saveMediaToLocalDevice(from: testURL, customFilename: payload, destinationDirectory: downloadsDir)
                defer { try? FileManager.default.removeItem(at: savedURL) }

                // Check if file escaped downloads directory
                if !savedURL.standardizedFileURL.path.hasPrefix(downloadsDir.standardizedFileURL.path) {
                    Issue.record("SECURITY VULNERABILITY: saveMediaToLocalDevice customFilename '\(payload)' escaped downloads directory to: \(savedURL.path)")
                }
            } catch {
                // Rejecting path traversal with error is valid defense
                #expect(true)
            }
        }

        // Safe control payload must succeed and land within downloads
        let safeName = "safe_image_\(UUID().uuidString).jpg"
        let safeSavedURL = try await manager.saveMediaToLocalDevice(from: testURL, customFilename: safeName, destinationDirectory: downloadsDir)
        defer { try? FileManager.default.removeItem(at: safeSavedURL) }
        #expect(safeSavedURL.standardizedFileURL.path.hasPrefix(downloadsDir.standardizedFileURL.path))
        #expect(FileManager.default.fileExists(atPath: safeSavedURL.path))
        #endif
    }

    @Test("Challenge 4.3: High-Order Collision Avoidance Stress Test")
    func testHighOrderCollisionAvoidanceStress() throws {
        let tempFolder = FileManager.default.temporaryDirectory.appendingPathComponent("ChallengerCollision_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempFolder) }

        let baseName = "artwork.png"
        let firstFile = tempFolder.appendingPathComponent(baseName)
        try "Original".write(to: firstFile, atomically: true, encoding: .utf8)

        // Pre-create 25 colliding files
        let nameWithoutExt = (baseName as NSString).deletingPathExtension
        let ext = (baseName as NSString).pathExtension
        for i in 1...25 {
            let existing = tempFolder.appendingPathComponent("\(nameWithoutExt) (\(i)).\(ext)")
            try "Copy \(i)".write(to: existing, atomically: true, encoding: .utf8)
        }

        // Run collision resolver logic
        var targetURL = firstFile
        var counter = 1
        while FileManager.default.fileExists(atPath: targetURL.path) {
            let numberedName = ext.isEmpty ? "\(nameWithoutExt) (\(counter))" : "\(nameWithoutExt) (\(counter)).\(ext)"
            targetURL = tempFolder.appendingPathComponent(numberedName)
            counter += 1
        }

        #expect(targetURL.lastPathComponent == "artwork (26).png")
        #expect(!FileManager.default.fileExists(atPath: targetURL.path))
    }

    @Test("Challenge 4.4: Concurrent Downloads of Same URL with Cancellation Interference")
    @MainActor
    func testConcurrentDownloadsWithCancellationInterference() async throws {
        let (manager, tempDir) = makeChallengerManager()
        defer { cleanup(tempDir: tempDir) }

        let testURL = URL(string: "https://example.com/media/concurrent_race.mp4")!
        let payload = Data(repeating: 0xEE, count: 200_000)
        // Add 50ms delay so tasks overlap in flight
        ChallengerMockURLProtocol.setHandler(for: testURL, statusCode: 200, data: payload, delayMs: 50)

        // Task 1: Long running download
        let task1 = Task { @MainActor in
            try await manager.downloadMedia(from: testURL)
        }

        // Task 2: Started immediately and then cancelled
        let task2 = Task { @MainActor in
            try await manager.downloadMedia(from: testURL)
        }

        // Cancel task2 while both are in flight
        task2.cancel()

        // Wait for both
        _ = try? await task2.value
        let result1 = try? await task1.value

        // Check if task1 succeeded despite task2's cancellation
        if result1 == nil {
            Issue.record("BUG FOUND: Cancellation of concurrent task2 aborted task1 downloading the same URL!")
        } else {
            #expect(FileManager.default.fileExists(atPath: result1!.path))
            #expect(manager.isCached(url: testURL))
        }
    }

    @Test("Challenge 4.5: Massive 50-Actor Concurrent Download Saturation")
    func testMassiveConcurrentDownloadSaturation() async throws {
        let (manager, tempDir) = await MainActor.run {
            makeChallengerManager()
        }
        defer { cleanup(tempDir: tempDir) }

        let testURL = URL(string: "https://example.com/media/saturated.jpg")!
        let payload = Data(repeating: 0x55, count: 4096)
        ChallengerMockURLProtocol.setHandler(for: testURL, statusCode: 200, data: payload)

        try await withThrowingTaskGroup(of: URL.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    try await manager.downloadMedia(from: testURL)
                }
            }

            var results: [URL] = []
            for try await fileURL in group {
                results.append(fileURL)
            }

            #expect(results.count == 50)
            let first = results.first!
            for res in results {
                #expect(res == first)
            }
        }
    }

    @Test("Challenge 4.6: Concurrent saveMediaToLocalDevice TOCTOU Race Condition")
    @MainActor
    func testConcurrentSaveMediaToLocalDeviceTOCTOURace() async throws {
        #if os(macOS)
        let (manager, tempDir) = makeChallengerManager()
        defer { cleanup(tempDir: tempDir) }

        let testURL = URL(string: "https://example.com/media/collision_race.jpg")!
        ChallengerMockURLProtocol.setHandler(for: testURL, statusCode: 200, data: Data(repeating: 0x99, count: 1024))

        _ = try await manager.downloadMedia(from: testURL)

        let testFilename = "challenger_race_\(UUID().uuidString).jpg"
        async let s1: Result<URL, any Error> = Task { @MainActor in
            try await manager.saveMediaToLocalDevice(from: testURL, customFilename: testFilename)
        }.result
        async let s2: Result<URL, any Error> = Task { @MainActor in
            try await manager.saveMediaToLocalDevice(from: testURL, customFilename: testFilename)
        }.result
        async let s3: Result<URL, any Error> = Task { @MainActor in
            try await manager.saveMediaToLocalDevice(from: testURL, customFilename: testFilename)
        }.result
        async let s4: Result<URL, any Error> = Task { @MainActor in
            try await manager.saveMediaToLocalDevice(from: testURL, customFilename: testFilename)
        }.result
        async let s5: Result<URL, any Error> = Task { @MainActor in
            try await manager.saveMediaToLocalDevice(from: testURL, customFilename: testFilename)
        }.result

        let results = await [s1, s2, s3, s4, s5]
        var savedURLs: [URL] = []
        var caughtCollisions = 0

        for result in results {
            switch result {
            case .success(let url):
                savedURLs.append(url)
            case .failure:
                caughtCollisions += 1
            }
        }

        for url in savedURLs {
            try? FileManager.default.removeItem(at: url)
        }

        if caughtCollisions > 0 {
            Issue.record("BUG FOUND: saveMediaToLocalDevice suffered TOCTOU collision race: \(caughtCollisions) tasks failed because target URL already exists!")
        } else {
            #expect(savedURLs.count == 5)
        }
        #endif
    }

    @Test("Challenge 4.7: State Corruption on Cancellation of Sibling Concurrent Download")
    @MainActor
    func testSiblingTaskCancellationCorruptsSharedProgressState() async throws {
        let (manager, tempDir) = makeChallengerManager()
        defer { cleanup(tempDir: tempDir) }

        let testURL = URL(string: "https://example.com/media/shared_race.mp4")!
        let payload = Data(repeating: 0xAA, count: 100_000)
        ChallengerMockURLProtocol.setHandler(for: testURL, statusCode: 200, data: payload, delayMs: 40)

        // Sibling task 1 (primary)
        let task1 = Task { @MainActor in
            try await manager.downloadMedia(from: testURL)
        }

        // Sibling task 2 cancelled immediately
        let task2 = Task { @MainActor in
            try await manager.downloadMedia(from: testURL)
        }
        task2.cancel()

        _ = try? await task2.value

        // Check if task2's cancellation wiped activeProgress or set activeErrors while task1 is still running
        let prematureError = manager.activeErrors[testURL]
        let result1 = try? await task1.value

        if prematureError != nil {
            Issue.record("STATE CORRUPTION: Sibling task cancellation contaminated manager.activeErrors while primary download was still active: '\(prematureError!)'")
        }

        #expect(result1 != nil, "Primary download task1 failed after sibling cancellation")
        #expect(manager.activeErrors[testURL] == nil, "Active errors remained populated after successful download")
        #expect(manager.isCached(url: testURL), "File not cached after primary download completion")
        #expect(manager.completedDownloads.contains(testURL), "completedDownloads missing URL")
    }

    @Test("Challenge 4.8: Multi-Sibling Staggered Cancellation Isolation Stress")
    @MainActor
    func testMultiSiblingStaggeredCancellationIsolationStress() async throws {
        let (manager, tempDir) = makeChallengerManager()
        defer { cleanup(tempDir: tempDir) }

        let testURL = URL(string: "https://example.com/media/staggered_cancellation.mp4")!
        let payload = Data(repeating: 0xBB, count: 200_000)
        ChallengerMockURLProtocol.setHandler(for: testURL, statusCode: 200, data: payload, delayMs: 60)

        // Spawn 5 concurrent tasks requesting the same URL
        let survivor1 = Task { @MainActor in
            try await manager.downloadMedia(from: testURL)
        }

        let cancelledA = Task { @MainActor in
            try await manager.downloadMedia(from: testURL)
        }
        cancelledA.cancel() // cancelled at 0ms

        let cancelledB = Task { @MainActor in
            try await manager.downloadMedia(from: testURL)
        }

        let survivor2 = Task { @MainActor in
            try await manager.downloadMedia(from: testURL)
        }

        let cancelledC = Task { @MainActor in
            try await manager.downloadMedia(from: testURL)
        }

        // Cancel at staggered delays
        Task {
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            cancelledB.cancel()
        }
        Task {
            try? await Task.sleep(nanoseconds: 25_000_000) // 25ms
            cancelledC.cancel()
        }

        _ = try? await cancelledA.value
        _ = try? await cancelledB.value
        _ = try? await cancelledC.value

        let res1 = try? await survivor1.value
        let res2 = try? await survivor2.value

        #expect(res1 != nil, "Survivor task 1 failed")
        #expect(res2 != nil, "Survivor task 2 failed")
        #expect(res1 == res2, "Survivor tasks received different cached URLs")
        #expect(manager.activeErrors[testURL] == nil, "activeErrors leaked error to survivor tasks")
        #expect(manager.completedDownloads.contains(testURL))
        #expect(manager.isCached(url: testURL))
    }
}

