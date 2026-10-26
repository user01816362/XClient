import Foundation
import XKit
import XKitModels
import XKitTransport
import XKitAPI
import XKitAuth
import XKitTesting

/// Deterministic, stateful offline mock data provider conforming to 100% Swift 6 strict concurrency.
@MainActor
public final class MockDataProvider: Sendable {
    public static let shared = MockDataProvider()

    // MARK: - Current User & Profiles
    public var currentUser: XUser
    public var currentProfile: UserProfile
    public var users: [String: XUser]
    public var userProfiles: [String: UserProfile]

    // MARK: - Raw Wire SDK Collections (XKitModels)
    public var timelinePosts: [XPost]
    public var userPosts: [XPost]
    public var bookmarks: [XPost]
    public var userLikes: [String: Set<String>]

    // MARK: - Post ID Generation Sequence
    private var postSequence: Int = 0

    // MARK: - Rich Client Domain Collections (XClient/Models)
    public var postItems: [PostItem]

    // MARK: - Initialization
    public init() {
        // 1. Initialize Users
        let me = XUser(
            id: "usr_me_001",
            name: "Liquid Glass",
            username: "liquidglass",
            description: "Crafting native Apple experiences with Liquid Glass materials, adaptive layouts, and 100% Swift 6 strict concurrency. 🍎✨",
            verified: true,
            profileImageUrl: "https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=256&h=256&q=80"
        )
        let meAlias = XUser(
            id: "990001",
            name: "Liquid Glass",
            username: "liquidglass",
            description: "Crafting native Apple experiences with Liquid Glass materials, adaptive layouts, and 100% Swift 6 strict concurrency. 🍎✨",
            verified: true,
            profileImageUrl: "https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=256&h=256&q=80"
        )
        let swift = XUser(
            id: "usr_author_002",
            name: "Swift Core Team",
            username: "swift_lang",
            description: "The Swift Programming Language. Fast, safe, expressive, and strictly concurrent.",
            verified: true,
            profileImageUrl: "https://images.unsplash.com/photo-1579546929518-9e396f3cc809?auto=format&fit=crop&w=256&h=256&q=80",
            verifiedType: "business"
        )
        let elena = XUser(
            id: "usr_author_003",
            name: "Elena Rostova",
            username: "elena_hig",
            description: "Principal Interface Designer. Exploring Dynamic Type scaling, VoiceOver rotors, and adaptive split view ergonomics.",
            verified: true,
            profileImageUrl: "https://images.unsplash.com/photo-1580489944761-15a19d654956?auto=format&fit=crop&w=256&h=256&q=80"
        )
        let marcus = XUser(
            id: "usr_author_004",
            name: "Marcus Vance",
            username: "marcus_vance",
            description: "Low-latency systems, Swift 6 data-race safety, and async streams. Always profile before optimizing.",
            verified: false,
            profileImageUrl: "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=256&h=256&q=80"
        )
        let alex = XUser(
            id: "usr_author_005",
            name: "Alex Chen",
            username: "alexchen",
            description: "Building cool stuff with SwiftUI. Coffee lover ☕️",
            verified: false,
            profileImageUrl: nil
        )
        let radar = XUser(
            id: "usr_author_006",
            name: "Release Radar",
            username: "release_radar",
            description: "Automated tracker for Xcode, iOS, macOS, and SDK beta releases.",
            verified: true,
            profileImageUrl: "https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?auto=format&fit=crop&w=256&h=256&q=80",
            verifiedType: "business"
        )
        let sarah = XUser(
            id: "990002",
            name: "Sarah Jenkins",
            username: "sarah_design",
            description: "Design Systems & SwiftUI specialist.",
            verified: true,
            profileImageUrl: "https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=256&h=256&q=80"
        )

        self.currentUser = me
        self.users = [
            me.id: me,
            meAlias.id: meAlias,
            swift.id: swift,
            elena.id: elena,
            marcus.id: marcus,
            alex.id: alex,
            radar.id: radar,
            sarah.id: sarah
        ]
        self.userLikes = [
            me.id: ["post_1001", "post_1007"],
            meAlias.id: ["post_1001", "post_1007"]
        ]

        // 2. Initialize User Profiles
        self.currentProfile = UserProfile(
            user: me,
            headerImageUrl: URL(string: "https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?auto=format&fit=crop&w=1200&h=400&q=80"),
            bio: me.description,
            location: "Cupertino, CA",
            websiteUrl: URL(string: "https://developer.apple.com"),
            joinedDate: Date(timeIntervalSince1970: 1696118400), // Oct 2023
            followersCount: 18420,
            followingCount: 421,
            postsCount: 142,
            isFollowing: false
        )
        self.userProfiles = [
            me.id: currentProfile,
            meAlias.id: currentProfile,
            swift.id: UserProfile(user: swift, joinedDate: Date(timeIntervalSince1970: 1401580800), followersCount: 245000, followingCount: 12, postsCount: 890),
            elena.id: UserProfile(user: elena, location: "London, UK", joinedDate: Date(timeIntervalSince1970: 1546300800), followersCount: 34200, followingCount: 512, postsCount: 420),
            marcus.id: UserProfile(user: marcus, location: "Seattle, WA", joinedDate: Date(timeIntervalSince1970: 1577836800), followersCount: 12400, followingCount: 890, postsCount: 310),
            alex.id: UserProfile(user: alex, location: "San Francisco, CA", joinedDate: Date(timeIntervalSince1970: 1640995200), followersCount: 1450, followingCount: 620, postsCount: 95),
            radar.id: UserProfile(user: radar, joinedDate: Date(timeIntervalSince1970: 1514764800), followersCount: 89000, followingCount: 5, postsCount: 2400),
            sarah.id: UserProfile(user: sarah, location: "San Francisco, CA", joinedDate: Date(timeIntervalSince1970: 1609459200), followersCount: 42000, followingCount: 340, postsCount: 510)
        ]

        // 3. Initialize Media Fixtures
        let mediaLaunch1 = MediaAttachment(
            id: "m_launch_01",
            url: URL(string: "https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?auto=format&fit=crop&w=1200&h=800&q=80")!,
            previewUrl: URL(string: "https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?auto=format&fit=crop&w=400&h=267&q=80"),
            type: .photo,
            width: 1200,
            height: 800,
            altText: "XClient iPhone layout mockup"
        )
        let mediaLaunch2 = MediaAttachment(
            id: "m_launch_02",
            url: URL(string: "https://images.unsplash.com/photo-1550745165-9bc0b252726f?auto=format&fit=crop&w=1200&h=800&q=80")!,
            previewUrl: URL(string: "https://images.unsplash.com/photo-1550745165-9bc0b252726f?auto=format&fit=crop&w=400&h=267&q=80"),
            type: .photo,
            width: 1200,
            height: 800,
            altText: "XClient iPad split view layout mockup"
        )
        let mediaDiagram = MediaAttachment(
            id: "m_diag_01",
            url: URL(string: "https://images.unsplash.com/photo-1507238691740-187a5b1d37b8?auto=format&fit=crop&w=1200&h=675&q=80")!,
            previewUrl: URL(string: "https://images.unsplash.com/photo-1507238691740-187a5b1d37b8?auto=format&fit=crop&w=400&h=225&q=80"),
            type: .photo,
            width: 1200,
            height: 675,
            altText: "Adaptive split view architecture diagram"
        )
        let mediaVideo = MediaAttachment(
            id: "m_video_01",
            url: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!,
            previewUrl: URL(string: "https://images.unsplash.com/photo-1536240478700-b869070f9279?auto=format&fit=crop&w=1200&h=675&q=80"),
            type: .video,
            width: 1920,
            height: 1080,
            altText: "Media downloader video clip",
            durationSeconds: 42.5
        )
        let mediaTheme1 = MediaAttachment(id: "m_th_1", url: URL(string: "https://images.unsplash.com/photo-1579546929518-9e396f3cc809?auto=format&fit=crop&w=600&h=600&q=80")!, type: .photo, width: 600, height: 600, altText: "Light Theme")
        let mediaTheme2 = MediaAttachment(id: "m_th_2", url: URL(string: "https://images.unsplash.com/photo-1550745165-9bc0b252726f?auto=format&fit=crop&w=600&h=600&q=80")!, type: .photo, width: 600, height: 600, altText: "Dark Dim Theme")
        let mediaTheme3 = MediaAttachment(id: "m_th_3", url: URL(string: "https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?auto=format&fit=crop&w=600&h=600&q=80")!, type: .photo, width: 600, height: 600, altText: "Lights Out Theme")
        let mediaTheme4 = MediaAttachment(id: "m_th_4", url: URL(string: "https://images.unsplash.com/photo-1507238691740-187a5b1d37b8?auto=format&fit=crop&w=600&h=600&q=80")!, type: .photo, width: 600, height: 600, altText: "High Contrast Theme")

        // 4. Initialize Post Items
        let p1 = PostItem(
            id: "post_1001",
            text: "Introducing XClient: a native client for iPhone, iPad, and Mac! Built with pure SwiftUI, Liquid Glass materials, and 100% Swift 6 strict concurrency. 🚀 #SwiftUI #AppleHIG #Swift6 https://developer.apple.com",
            author: me,
            createdAt: Date().addingTimeInterval(-300),
            conversationId: "post_1001",
            mediaAttachments: [mediaLaunch1, mediaLaunch2],
            replyCount: 1420,
            repostCount: 3890,
            likeCount: 14200,
            bookmarkCount: 892,
            isLiked: true,
            isBookmarked: true
        )
        let p2 = PostItem(
            id: "post_1002",
            text: "Why Swift 6 complete strict concurrency matters for client architecture:\n\n1. Zero data races across actor boundaries guaranteed by compiler static analysis.\n2. Predictable UI state updates on @MainActor without accidental background thread hops.\n3. Background polling engines and URLSession download actors run safely in parallel without locks or Mutex boilerplate.\n\nMigrating our codebase from Swift 5 unchecked Sendable to Swift 6 required careful auditing of completion handlers and global state, but the stability gains in production are immense. If you haven't enabled -strict-concurrency=complete yet, start by turning on upcoming features today! #Concurrency #Swift6 #DevNotes",
            author: marcus,
            createdAt: Date().addingTimeInterval(-1680),
            conversationId: "post_1002",
            replyCount: 84,
            repostCount: 215,
            likeCount: 1140,
            bookmarkCount: 310
        )
        let p3 = PostItem(
            id: "post_1003",
            text: "Adaptive navigation principles for multiplatform Apple apps (Thread 🧵):\n\nOn compact iPhones, a bottom TabBar provides optimal one-handed reachability. On iPad and Mac, a NavigationSplitView with collapsible Sidebar preserves horizontal screen real estate. Let's break down the implementation details 👇",
            author: elena,
            createdAt: Date().addingTimeInterval(-7200),
            conversationId: "post_1003",
            mediaAttachments: [mediaDiagram],
            replyCount: 312,
            repostCount: 640,
            likeCount: 4820,
            bookmarkCount: 512,
            isBookmarked: true
        )
        let p4 = PostItem(
            id: "post_1004",
            text: "1/3 When designing with Liquid Glass materials, remember that translucent blur layers must always prioritize text legibility. When the user enables 'Reduce Transparency' in Accessibility settings, fall back to solid semantic background tokens immediately.",
            author: elena,
            createdAt: Date().addingTimeInterval(-6600),
            conversationId: "post_1003",
            inReplyToPostId: "post_1003",
            replyCount: 45,
            repostCount: 88,
            likeCount: 920,
            bookmarkCount: 64
        )
        let p5 = PostItem(
            id: "post_1005",
            text: "2/3 Thanks to @liquidglass and @swift_lang for the inspiration! You can inspect the complete source and HIG guidelines at https://developer.apple.com/design/human-interface-guidelines/",
            author: elena,
            createdAt: Date().addingTimeInterval(-6000),
            conversationId: "post_1003",
            inReplyToPostId: "post_1004",
            replyCount: 28,
            repostCount: 42,
            likeCount: 610,
            bookmarkCount: 39
        )
        let p6 = PostItem(
            id: "post_1006",
            text: "Demo: Video playback and inline streaming download pipeline in action. Right-click or long-press to save directly to Downloads (macOS) or Photos (iOS)! 🎥✨",
            author: radar,
            createdAt: Date().addingTimeInterval(-14400),
            conversationId: "post_1006",
            mediaAttachments: [mediaVideo],
            replyCount: 95,
            repostCount: 410,
            likeCount: 2890,
            bookmarkCount: 740,
            isBookmarked: true
        )
        let p7 = PostItem(
            id: "post_1007",
            text: "Fantastic work by the community showcasing modern Swift multiplatform app development. Check out the thread below! 🧡",
            author: swift,
            createdAt: Date().addingTimeInterval(-21600),
            conversationId: "post_1007",
            replyCount: 120,
            repostCount: 890,
            likeCount: 5420,
            bookmarkCount: 420,
            isLiked: true,
            quotedPost: .post(p1)
        )
        let p8 = PostItem(
            id: "post_1008",
            text: "Just switched my desktop client to XClient. The macOS sidebar shortcuts are so fast! Command+1 for Timeline, Command+B for Bookmarks.",
            author: alex,
            createdAt: Date().addingTimeInterval(-43200),
            conversationId: "post_1008",
            replyCount: 2,
            repostCount: 4,
            likeCount: 38,
            bookmarkCount: 1
        )
        let p9 = PostItem(
            id: "post_1009",
            text: "Four distinct color themes in XClient: Light Mode, Dark Dim (Navy), Dark Lights Out (OLED True Black), and High-Contrast Glass. Which one is your daily driver? 🎨",
            author: me,
            createdAt: Date().addingTimeInterval(-86400),
            conversationId: "post_1009",
            mediaAttachments: [mediaTheme1, mediaTheme2, mediaTheme3, mediaTheme4],
            replyCount: 540,
            repostCount: 310,
            likeCount: 6200,
            bookmarkCount: 1100,
            isBookmarked: true
        )
        let p10 = PostItem(
            id: "post_1010",
            text: "✨ 🚀 💻 ☕️ 🎉 #HelloFromSwift6",
            author: alex,
            createdAt: Date().addingTimeInterval(-172800),
            conversationId: "post_1010",
            replyCount: 0,
            repostCount: 1,
            likeCount: 12,
            bookmarkCount: 0
        )

        self.postItems = [p1, p2, p3, p4, p5, p6, p7, p8, p9, p10]
        self.timelinePosts = postItems.map(\.asXPost)
        self.userPosts = postItems.filter { $0.author.id == me.id }.map(\.asXPost)
        self.bookmarks = postItems.filter(\.isBookmarked).map(\.asXPost)
    }

    // MARK: - Interactive Mutation Operations
    @discardableResult
    public func addPost(text: String, mediaAttachments: [MediaAttachment] = []) -> XPost {
        postSequence += 1
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let uuidSuffix = UUID().uuidString.prefix(8).lowercased()
        let newId = "post_\(timestamp)_\(postSequence)_\(uuidSuffix)"
        let newItem = PostItem(
            id: newId,
            text: text,
            author: currentUser,
            createdAt: Date(),
            conversationId: newId,
            mediaAttachments: mediaAttachments
        )
        postItems.insert(newItem, at: 0)
        let xPost = newItem.asXPost
        timelinePosts.insert(xPost, at: 0)
        userPosts.insert(xPost, at: 0)
        return xPost
    }

    @discardableResult
    public func deletePost(id: String) -> Bool {
        let found = postItems.contains { $0.id == id } || timelinePosts.contains { $0.id == id }
        guard found else { return false }

        if let idx = postItems.firstIndex(where: { $0.id == id }) {
            postItems.remove(at: idx)
        }
        if let idx = timelinePosts.firstIndex(where: { $0.id == id }) {
            timelinePosts.remove(at: idx)
        }
        if let idx = userPosts.firstIndex(where: { $0.id == id }) {
            userPosts.remove(at: idx)
        }
        if let idx = bookmarks.firstIndex(where: { $0.id == id }) {
            bookmarks.remove(at: idx)
        }
        for (userId, var likedSet) in userLikes {
            if likedSet.remove(id) != nil {
                userLikes[userId] = likedSet
            }
        }
        return true
    }

    @discardableResult
    public func toggleBookmark(postId: String, forceState: Bool? = nil) -> Bool {
        guard let index = postItems.firstIndex(where: { $0.id == postId }) else {
            return false
        }
        let currentState = postItems[index].isBookmarked
        let newState = forceState ?? !currentState

        if newState != currentState {
            postItems[index].isBookmarked = newState
            if newState {
                postItems[index].bookmarkCount += 1
            } else {
                postItems[index].bookmarkCount = max(0, postItems[index].bookmarkCount - 1)
            }

            let xPost = postItems[index].asXPost
            if newState {
                if !bookmarks.contains(where: { $0.id == postId }) {
                    bookmarks.insert(xPost, at: 0)
                }
            } else {
                bookmarks.removeAll { $0.id == postId }
            }
        }
        return newState
    }

    @discardableResult
    public func toggleLike(postId: String, forceState: Bool? = nil) -> Bool {
        guard let index = postItems.firstIndex(where: { $0.id == postId }) else {
            return false
        }
        let newState = forceState ?? !postItems[index].isLiked
        postItems[index].isLiked = newState
        postItems[index].likeCount = max(0, postItems[index].likeCount + (newState ? 1 : -1))

        var currentLikes = userLikes[currentUser.id] ?? []
        if newState {
            currentLikes.insert(postId)
        } else {
            currentLikes.remove(postId)
        }
        userLikes[currentUser.id] = currentLikes

        return newState
    }

    @discardableResult
    public func toggleRepost(postId: String) -> Bool {
        guard let index = postItems.firstIndex(where: { $0.id == postId }) else {
            return false
        }
        let newState = !postItems[index].isReposted
        postItems[index].isReposted = newState
        postItems[index].repostCount = max(0, postItems[index].repostCount + (newState ? 1 : -1))
        return newState
    }

    public func resetToDefaults() {
        let fresh = MockDataProvider()
        self.currentUser = fresh.currentUser
        self.currentProfile = fresh.currentProfile
        self.users = fresh.users
        self.userProfiles = fresh.userProfiles
        self.timelinePosts = fresh.timelinePosts
        self.userPosts = fresh.userPosts
        self.bookmarks = fresh.bookmarks
        self.postItems = fresh.postItems
        self.userLikes = fresh.userLikes
        self.postSequence = 0
    }

    // MARK: - Query Helpers
    public func postsForUser(id: String) -> [PostItem] {
        postItems.filter { $0.author.id == id && $0.inReplyToPostId == nil }
    }

    public func repliesForUser(id: String) -> [PostItem] {
        postItems.filter { $0.author.id == id && $0.inReplyToPostId != nil }
    }

    public func mediaForUser(id: String) -> [PostItem] {
        postItems.filter { $0.author.id == id && !$0.mediaAttachments.isEmpty }
    }

    public func likesForUser(id: String) -> [PostItem] {
        if id == currentUser.id {
            return postItems.filter(\.isLiked)
        }
        if let likedIds = userLikes[id] {
            return postItems.filter { likedIds.contains($0.id) }
        }
        return postItems.filter { $0.author.id == id && $0.isLiked }
    }

    // MARK: - XClient Factory & HTTP Interceptor

    /// Creates an XClient bound directly to this MockDataProvider instance.
    public func makeMockClient() -> XClient {
        let mockTransport = MockTransport()
        mockTransport.setHandler { [weak self] request in
            guard let self = self else {
                throw XKitError.networkError
            }
            return try await self.handle(request: request)
        }
        return XClient(transport: mockTransport)
    }

    /// Convenience factory creating an XClient bound to an explicit provider, or `MockDataProvider.shared` by default.
    public static func makeMockClient(provider: MockDataProvider? = nil) -> XClient {
        let target = provider ?? MockDataProvider.shared
        return target.makeMockClient()
    }

    private enum RouteError: Error, Sendable {
        case badRequest(detail: String)
        case notFound(detail: String)
    }

    private struct PaginationOutcome: Sendable {
        let posts: [XPost]
        let resultCount: Int
        let nextToken: String?
        let previousToken: String?
    }

    private static func paginatePosts(
        _ sourcePosts: [XPost],
        request: HTTPRequest,
        defaultLimit: Int = 20
    ) throws -> PaginationOutcome {
        var limit = defaultLimit
        var startIndex = 0
        let totalCount = sourcePosts.count

        if let components = URLComponents(url: request.url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems {

            // 1. Parse max_results with validation & negative clamping guard
            if let maxResultsStr = queryItems.first(where: { $0.name == "max_results" })?.value {
                guard let parsedLimit = Int(maxResultsStr) else {
                    throw RouteError.badRequest(detail: "The 'max_results' query parameter must be an integer.")
                }
                if parsedLimit < 0 {
                    throw RouteError.badRequest(detail: "The 'max_results' query parameter must be a non-negative integer.")
                }
                limit = max(0, parsedLimit)
            }

            // 2. Parse pagination_token
            if let token = queryItems.first(where: { $0.name == "pagination_token" })?.value, !token.isEmpty {
                if token == "cursor_next_token_100" {
                    // Backward-compatibility alias for legacy test harness
                    startIndex = min(5, totalCount)
                } else if token.hasPrefix("cursor_idx_") {
                    let offsetStr = String(token.dropFirst("cursor_idx_".count))
                    guard let offset = Int(offsetStr), offset >= 0 else {
                        throw RouteError.badRequest(detail: "The 'pagination_token' is malformed.")
                    }
                    startIndex = min(offset, totalCount)
                } else if token.hasPrefix("cursor_offset_") {
                    let offsetStr = String(token.dropFirst("cursor_offset_".count))
                    guard let offset = Int(offsetStr), offset >= 0 else {
                        throw RouteError.badRequest(detail: "The 'pagination_token' is malformed.")
                    }
                    startIndex = min(offset, totalCount)
                } else if token.hasPrefix("next_cursor_") {
                    // Test suite token compatibility (XClientServiceTests:46)
                    let offsetStr = String(token.dropFirst("next_cursor_".count))
                    let offset = Int(offsetStr) ?? 0
                    startIndex = min(max(0, offset), totalCount)
                } else if let postIdx = sourcePosts.firstIndex(where: { $0.id == token }) {
                    startIndex = min(postIdx + 1, totalCount)
                } else {
                    throw RouteError.badRequest(detail: "The 'pagination_token' is invalid or expired.")
                }
            }
        }

        // Defensive clamping on boundaries
        let safeStart = max(0, min(startIndex, totalCount))
        let safeLimit = max(0, limit)
        let endIndex = min(safeStart + safeLimit, totalCount)
        let page = Array(sourcePosts[safeStart..<endIndex])

        // Cursor generation
        let nextToken: String? = (safeLimit > 0 && endIndex < totalCount) ? "cursor_idx_\(endIndex)" : nil
        let previousToken: String? = (safeStart > 0) ? "cursor_idx_\(max(0, safeStart - safeLimit))" : nil

        return PaginationOutcome(
            posts: page,
            resultCount: page.count,
            nextToken: nextToken,
            previousToken: previousToken
        )
    }

    private static func makeProblemResponse(
        status: Int,
        title: String,
        detail: String,
        type: String = "https://api.twitter.com/2/problems/invalid-request"
    ) -> HTTPResponse {
        let problem = APIProblemDetails(title: title, detail: detail, type: type, status: status)
        let data = (try? JSONEncoder().encode(problem)) ?? Data()
        return HTTPResponse(
            statusCode: status,
            headers: ["Content-Type": "application/problem+json"],
            data: data
        )
    }

    /// Static forwarding handler for legacy / shared singleton callers.
    @MainActor
    public static func handle(request: HTTPRequest) async throws -> HTTPResponse {
        try await MockDataProvider.shared.handle(request: request)
    }

    /// Handles an incoming HTTPRequest against this instance's mock state.
    @MainActor
    public func handle(request: HTTPRequest) async throws -> HTTPResponse {
        let rawPath = request.url.path
        let trimmedPath = rawPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let segments = trimmedPath.split(separator: "/").map(String.init)
        let method = request.method
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        do {
            // MARK: 1. Authenticated User Profile (`GET /2/users/me`)
            if segments == ["2", "users", "me"] && method == .get {
                let payload = SingleResourceResponse(data: self.currentUser)
                let data = try encoder.encode(payload)
                return HTTPResponse(statusCode: 200, headers: ["Content-Type": "application/json"], data: data)
            }

            // MARK: 2. User Lookup by Username (`GET /2/users/by/username/{username}`)
            if segments.count == 5 && segments[0] == "2" && segments[1] == "users" && segments[2] == "by" && segments[3] == "username" && method == .get {
                let username = segments[4]
                if let user = self.users.values.first(where: { $0.username.lowercased() == username.lowercased() }) {
                    let payload = SingleResourceResponse(data: user)
                    let data = try encoder.encode(payload)
                    return HTTPResponse(statusCode: 200, headers: ["Content-Type": "application/json"], data: data)
                } else {
                    return MockDataProvider.makeProblemResponse(
                        status: 404,
                        title: "Not Found",
                        detail: "Could not find user with username: \(username)",
                        type: "https://api.twitter.com/2/problems/resource-not-found"
                    )
                }
            }

            // MARK: 3. User Reverse-Chronological Home Timeline (`GET /2/users/{id}/timelines/reverse_chronological`)
            if segments.count == 5 && segments[0] == "2" && segments[1] == "users" && segments[3] == "timelines" && segments[4] == "reverse_chronological" && method == .get {
                let userId = segments[2]
                let targetId = (userId == "me") ? self.currentUser.id : userId
                guard self.users[targetId] != nil || targetId == self.currentUser.id else {
                    return MockDataProvider.makeProblemResponse(
                        status: 404,
                        title: "Not Found",
                        detail: "Could not find user with id: \(userId)",
                        type: "https://api.twitter.com/2/problems/resource-not-found"
                    )
                }

                let outcome = try MockDataProvider.paginatePosts(self.timelinePosts, request: request)
                let response = PaginatedResponse(
                    data: outcome.posts,
                    resultCount: outcome.resultCount,
                    nextToken: outcome.nextToken,
                    previousToken: outcome.previousToken
                )
                let data = try encoder.encode(response)
                return HTTPResponse(statusCode: 200, headers: ["Content-Type": "application/json"], data: data)
            }

            // MARK: 4. User Posted Tweets (`GET /2/users/{id}/tweets`)
            if segments.count == 4 && segments[0] == "2" && segments[1] == "users" && segments[3] == "tweets" && method == .get {
                let userId = segments[2]
                let targetId = (userId == "me") ? self.currentUser.id : userId
                guard self.users[targetId] != nil || targetId == self.currentUser.id else {
                    return MockDataProvider.makeProblemResponse(
                        status: 404,
                        title: "Not Found",
                        detail: "Could not find user with id: \(userId)",
                        type: "https://api.twitter.com/2/problems/resource-not-found"
                    )
                }

                let userMatchingPosts = self.postItems
                    .filter { $0.author.id == targetId }
                    .map(\.asXPost)

                let outcome = try MockDataProvider.paginatePosts(userMatchingPosts, request: request)
                let response = PaginatedResponse(
                    data: outcome.posts,
                    resultCount: outcome.resultCount,
                    nextToken: outcome.nextToken,
                    previousToken: outcome.previousToken
                )
                let data = try encoder.encode(response)
                return HTTPResponse(statusCode: 200, headers: ["Content-Type": "application/json"], data: data)
            }

            // MARK: 5. Bookmarks Endpoints (`GET /2/users/{id}/bookmarks` & `POST /2/users/{id}/bookmarks`)
            if segments.count == 4 && segments[0] == "2" && segments[1] == "users" && segments[3] == "bookmarks" {
                if method == .get {
                    let outcome = try MockDataProvider.paginatePosts(self.bookmarks, request: request)
                    let response = PaginatedResponse(
                        data: outcome.posts,
                        resultCount: outcome.resultCount,
                        nextToken: outcome.nextToken,
                        previousToken: outcome.previousToken
                    )
                    let data = try encoder.encode(response)
                    return HTTPResponse(statusCode: 200, headers: ["Content-Type": "application/json"], data: data)
                } else if method == .post {
                    guard let body = request.body, !body.isEmpty else {
                        return MockDataProvider.makeProblemResponse(status: 400, title: "Bad Request", detail: "Request body cannot be empty.")
                    }
                    guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                        return MockDataProvider.makeProblemResponse(status: 400, title: "Bad Request", detail: "Invalid JSON format in request body.")
                    }
                    guard let postId = json["tweet_id"] as? String, !postId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        return MockDataProvider.makeProblemResponse(status: 400, title: "Bad Request", detail: "Field 'tweet_id' is required and must be a non-empty string.")
                    }

                    _ = self.toggleBookmark(postId: postId, forceState: true)
                    let payload: [String: Any] = ["data": ["bookmarked": true]]
                    let data = try JSONSerialization.data(withJSONObject: payload)
                    return HTTPResponse(statusCode: 200, headers: ["Content-Type": "application/json"], data: data)
                }
            }

            // MARK: 6. Remove Bookmark (`DELETE /2/users/{id}/bookmarks/{tweet_id}`)
            if segments.count == 5 && segments[0] == "2" && segments[1] == "users" && segments[3] == "bookmarks" && method == .delete {
                let postId = segments[4]
                _ = self.toggleBookmark(postId: postId, forceState: false)
                let payload: [String: Any] = ["data": ["bookmarked": false]]
                let data = try JSONSerialization.data(withJSONObject: payload)
                return HTTPResponse(statusCode: 200, headers: ["Content-Type": "application/json"], data: data)
            }

            // MARK: 7. User Lookup by ID (`GET /2/users/{id}`)
            if segments.count == 3 && segments[0] == "2" && segments[1] == "users" && method == .get {
                let userId = segments[2]
                if let user = self.users[userId] {
                    let payload = SingleResourceResponse(data: user)
                    let data = try encoder.encode(payload)
                    return HTTPResponse(statusCode: 200, headers: ["Content-Type": "application/json"], data: data)
                } else if userId == self.currentUser.id || userId == "me" {
                    let payload = SingleResourceResponse(data: self.currentUser)
                    let data = try encoder.encode(payload)
                    return HTTPResponse(statusCode: 200, headers: ["Content-Type": "application/json"], data: data)
                } else {
                    return MockDataProvider.makeProblemResponse(
                        status: 404,
                        title: "Not Found",
                        detail: "Could not find user with id: \(userId)",
                        type: "https://api.twitter.com/2/problems/resource-not-found"
                    )
                }
            }

            // MARK: 8. Tweet Creation (`POST /2/tweets`)
            if segments == ["2", "tweets"] && method == .post {
                guard let body = request.body, !body.isEmpty else {
                    return MockDataProvider.makeProblemResponse(status: 400, title: "Bad Request", detail: "Request body cannot be empty.")
                }
                guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                    return MockDataProvider.makeProblemResponse(status: 400, title: "Bad Request", detail: "Invalid JSON format in request body.")
                }
                guard let postText = json["text"] as? String, !postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return MockDataProvider.makeProblemResponse(status: 400, title: "Bad Request", detail: "Field 'text' is required and must not be empty.")
                }

                let created = self.addPost(text: postText)
                let payload = SingleResourceResponse(data: created)
                let data = try encoder.encode(payload)
                return HTTPResponse(statusCode: 201, headers: ["Content-Type": "application/json"], data: data)
            }

            // MARK: 9. Tweet Lookup & Deletion (`GET/DELETE /2/tweets/{id}`)
            if segments.count == 3 && segments[0] == "2" && segments[1] == "tweets" {
                let postId = segments[2]
                if method == .delete {
                    _ = self.deletePost(id: postId)
                    let payload: [String: Any] = ["data": ["deleted": true]]
                    let data = try JSONSerialization.data(withJSONObject: payload)
                    return HTTPResponse(statusCode: 200, headers: ["Content-Type": "application/json"], data: data)
                } else if method == .get {
                    if let post = self.timelinePosts.first(where: { $0.id == postId }) ?? self.postItems.first(where: { $0.id == postId })?.asXPost {
                        let payload = SingleResourceResponse(data: post)
                        let data = try encoder.encode(payload)
                        return HTTPResponse(statusCode: 200, headers: ["Content-Type": "application/json"], data: data)
                    } else {
                        return MockDataProvider.makeProblemResponse(
                            status: 404,
                            title: "Not Found",
                            detail: "Could not find tweet with id: \(postId)",
                            type: "https://api.twitter.com/2/problems/resource-not-found"
                        )
                    }
                }
            }

        } catch RouteError.badRequest(let detail) {
            return MockDataProvider.makeProblemResponse(status: 400, title: "Bad Request", detail: detail)
        } catch RouteError.notFound(let detail) {
            return MockDataProvider.makeProblemResponse(status: 404, title: "Not Found", detail: detail, type: "https://api.twitter.com/2/problems/resource-not-found")
        }

        // MARK: 10. Fallback: RFC 7807 404 Not Found for Undefined Routes
        return MockDataProvider.makeProblemResponse(
            status: 404,
            title: "Not Found",
            detail: "Cannot \(method.rawValue) /\(trimmedPath)",
            type: "https://api.twitter.com/2/problems/resource-not-found"
        )
    }
}
