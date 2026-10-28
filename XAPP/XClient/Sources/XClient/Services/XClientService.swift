import Foundation
import XKit
import XKitModels
import XKitTransport
import XKitAPI

/// Unified service protocol defining high-level operations for XClient.
/// Fully isolated to @MainActor to ensure zero-overhead binding to SwiftUI view models.
@MainActor
public protocol XClientServiceProtocol: Sendable {
    // MARK: - Core Contract Required by PROJECT.md
    func fetchHomeTimeline() async throws -> [XPost]
    func fetchUserProfile(id: String) async throws -> XUser
    func createPost(text: String) async throws -> XPost
    func bookmarkPost(id: String) async throws -> Bool
    func removeBookmark(id: String) async throws -> Bool

    // MARK: - Extended Service Capabilities for Milestones 2, 3 & 4
    func fetchHomeTimeline(paginationToken: String?, maxResults: Int) async throws -> PaginatedResponse<XPost>
    func fetchUserPosts(userId: String, paginationToken: String?, maxResults: Int) async throws -> PaginatedResponse<XPost>
    func fetchBookmarks(paginationToken: String?, maxResults: Int) async throws -> PaginatedResponse<XPost>
    func deletePost(id: String) async throws -> Bool
    func fetchCurrentUser() async throws -> XUser
    func fetchPostDetail(postId: String) async throws -> (post: XPost, replies: [XPost])
    func searchPosts(query: String, cursor: String?, maxResults: Int) async throws -> PaginatedResponse<XPost>
}

// MARK: - Default Implementations
extension XClientServiceProtocol {
    public func fetchHomeTimeline() async throws -> [XPost] {
        let response = try await fetchHomeTimeline(paginationToken: nil, maxResults: 20)
        return response.data
    }

    public func fetchHomeTimeline(paginationToken: String? = nil, maxResults: Int = 20) async throws -> PaginatedResponse<XPost> {
        try await fetchHomeTimeline(paginationToken: paginationToken, maxResults: maxResults)
    }

    public func fetchUserPosts(userId: String) async throws -> [XPost] {
        let response = try await fetchUserPosts(userId: userId, paginationToken: nil, maxResults: 20)
        return response.data
    }

    public func fetchBookmarks() async throws -> [XPost] {
        let response = try await fetchBookmarks(paginationToken: nil, maxResults: 20)
        return response.data
    }

    public func fetchPostDetail(postId: String) async throws -> (post: XPost, replies: [XPost]) {
        throw XKitError.apiError(title: "Post unavailable", detail: "Post details are not supported by this service.", type: nil)
    }

    public func searchPosts(query: String, cursor: String? = nil, maxResults: Int = 20) async throws -> PaginatedResponse<XPost> {
        throw XKitError.apiError(title: "Search unavailable", detail: "Search is not supported by this service.", type: nil)
    }

}

/// Concrete implementation of XClientServiceProtocol wrapping SDK services
/// with active credential management and Swift 6 concurrency safety.
@MainActor
public final class XClientService: XClientServiceProtocol, Sendable {
    // MARK: - Wrapped SDK Services
    public let users: UsersService
    public let posts: PostsService
    public let timelines: TimelinesService
    public let bookmarks: BookmarksService
    public let graphql: GraphQLTimelineService
    public let transport: HTTPTransport

    /// In-memory cache for live authors parsed from GraphQL timeline, thread, and search responses.
    public var userCache: [String: XUser] = [:]

    /// Global transport factory used when initializing XClientService without an explicit client.
    /// In production, defaults to `URLSessionTransport()`. Can be customized for test suites.
    public static var defaultTransportFactory: @Sendable () -> HTTPTransport = {
        URLSessionTransport()
    }

    // MARK: - Active Session State
    public private(set) var token: String
    public private(set) var currentUserId: String
    public private(set) var csrfToken: String?

    private var isMockSession: Bool {
        token == "mock_token" || token.starts(with: "mock_") || token.starts(with: "oauth_mock_")
    }

    // MARK: - Initializers

    /// Initializes with individual services, token, and currentUserId.
    public init(
        users: UsersService,
        posts: PostsService,
        timelines: TimelinesService,
        bookmarks: BookmarksService,
        graphql: GraphQLTimelineService? = nil,
        transport: HTTPTransport,
        token: String = "mock_token",
        currentUserId: String = "usr_me_001",
        csrfToken: String? = nil
    ) {
        self.users = users
        self.posts = posts
        self.timelines = timelines
        self.bookmarks = bookmarks
        self.graphql = graphql ?? GraphQLTimelineService(transport: transport)
        self.transport = transport
        self.token = token
        self.currentUserId = currentUserId
        self.csrfToken = csrfToken
    }

    /// Convenience initializer wrapping an XKit.XClient facade.
    public convenience init(
        client: XKit.XClient,
        token: String = "mock_token",
        currentUserId: String = "usr_me_001",
        csrfToken: String? = nil
    ) {
        self.init(
            users: client.users,
            posts: client.posts,
            timelines: client.timelines,
            bookmarks: client.bookmarks,
            graphql: client.graphql,
            transport: client.transport,
            token: token,
            currentUserId: currentUserId,
            csrfToken: csrfToken
        )
    }

    /// Shared singleton instance for unified access across UI components and view models.
    public static let shared = XClientService()

    /// Default initializer configured for live production execution with URLSessionTransport.
    /// Automatically connects to live X platform servers based on SessionManager state.
    public convenience init() {
        let session = SessionManager.shared
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
                        ProcessInfo.processInfo.environment["SWIFT_TESTING"] != nil ||
                        ProcessInfo.processInfo.arguments.contains(where: {
                            $0.contains("swiftpm-testing-helper") ||
                            $0.contains("xctest") ||
                            $0.contains("--verify") ||
                            $0.contains("--headless")
                        })

        switch session.currentState {
        case .authenticated(let account):
            if !account.token.starts(with: "oauth_mock_") && !account.token.starts(with: "mock_") {
                let transport = Self.defaultTransportFactory()
                let client = XKit.XClient(transport: transport)
                self.init(
                    client: client,
                    token: account.token,
                    currentUserId: account.id,
                    csrfToken: account.csrfToken
                )
                return
            }
        case .guest(let guestSession):
            let transport = Self.defaultTransportFactory()
            let client = XKit.XClient(transport: transport)
            self.init(
                client: client,
                token: guestSession.guestToken,
                currentUserId: "guest_\(guestSession.guestToken.prefix(8))",
                csrfToken: nil
            )
            return
        case .unauthenticated:
            if !isTesting {
                let transport = Self.defaultTransportFactory()
                let client = XKit.XClient(transport: transport)
                self.init(
                    client: client,
                    token: "",
                    currentUserId: "",
                    csrfToken: nil
                )
                return
            }
        }

        // Offline deterministic fallback exclusively when executed under testing harness
        let mockClient = MockDataProvider.makeMockClient()
        self.init(
            client: mockClient,
            token: "mock_token",
            currentUserId: MockDataProvider.shared.currentUser.id,
            csrfToken: nil
        )
    }

    // MARK: - Session Management
    public func updateCredentials(token: String, currentUserId: String, csrfToken: String? = nil) {
        self.token = token
        self.currentUserId = currentUserId
        self.csrfToken = csrfToken
    }

    // MARK: - Timeline Operations
    public func fetchHomeTimeline() async throws -> [XPost] {
        let response = try await fetchHomeTimeline(paginationToken: nil, maxResults: 20)
        return response.data
    }

    public func fetchHomeTimeline(paginationToken: String?, maxResults: Int) async throws -> PaginatedResponse<XPost> {
        let session = SessionManager.shared.currentState
        switch session {
        case .guest(let guestSession):
            if !guestSession.guestToken.isEmpty {
                do {
                    let liveParsed = try await graphql.fetchSearchTimelineParsed(
                        query: "min_faves:50 lang:en",
                        guestToken: guestSession.guestToken,
                        count: maxResults,
                        cursor: paginationToken
                    )
                    for (userId, user) in liveParsed.users {
                        self.userCache[userId] = user
                    }
                    if !liveParsed.posts.isEmpty {
                        return liveParsed.asPaginatedResponse
                    }
                } catch {
                    if isMockSession {
                        return try await timelines.reverseChronologicalHome(
                            userId: currentUserId,
                            token: token,
                            paginationToken: paginationToken,
                            maxResults: maxResults
                        )
                    }
                }
            }

        case .authenticated(let account):
            if account.authType == .webSession {
                let csrf = account.csrfToken ?? ""
                guard !account.token.isEmpty, !csrf.isEmpty else {
                    throw XKitError.apiError(title: "Session unavailable", detail: "Sign in again to load your timeline.", type: nil)
                }
                let liveParsed = try await graphql.fetchHomeTimeline(
                    authToken: account.token,
                    csrfToken: csrf,
                    userId: account.id,
                    rawCookies: account.rawCookieHeader,
                    count: maxResults,
                    cursor: paginationToken
                )
                for (userId, user) in liveParsed.users {
                    self.userCache[userId] = user
                }
                return liveParsed.asPaginatedResponse
            } else if !isMockSession && !currentUserId.isEmpty {
                return try await timelines.reverseChronologicalHome(
                    userId: currentUserId,
                    token: token,
                    paginationToken: paginationToken,
                    maxResults: maxResults
                )
            }

        case .unauthenticated:
            break
        }

        if isMockSession || currentUserId.isEmpty {
            return try await timelines.reverseChronologicalHome(
                userId: currentUserId.isEmpty ? MockDataProvider.shared.currentUser.id : currentUserId,
                token: token,
                paginationToken: paginationToken,
                maxResults: maxResults
            )
        }

        return try await timelines.reverseChronologicalHome(
            userId: currentUserId,
            token: token,
            paginationToken: paginationToken,
            maxResults: maxResults
        )
    }

    public func fetchUserPosts(userId: String, paginationToken: String? = nil, maxResults: Int = 20) async throws -> PaginatedResponse<XPost> {
        let session = SessionManager.shared.currentState
        if case .guest(let guest) = session, !guest.guestToken.isEmpty {
            if let liveUserTimeline = try? await graphql.fetchUserTweets(
                userId: userId,
                guestToken: guest.guestToken,
                count: maxResults,
                cursor: paginationToken
            ), !liveUserTimeline.posts.isEmpty {
                for (authorId, user) in liveUserTimeline.users {
                    self.userCache[authorId] = user
                }
                return liveUserTimeline.asPaginatedResponse
            }
        } else if case .authenticated(let account) = session, account.authType == .webSession, let csrf = account.csrfToken {
            if let liveUserTimeline = try? await graphql.fetchUserTweets(
                userId: userId,
                authToken: account.token,
                csrfToken: csrf,
                count: maxResults,
                cursor: paginationToken
            ), !liveUserTimeline.posts.isEmpty {
                for (authorId, user) in liveUserTimeline.users {
                    self.userCache[authorId] = user
                }
                return liveUserTimeline.asPaginatedResponse
            }
        }

        return try await timelines.userTweets(
            userId: userId,
            token: token,
            paginationToken: paginationToken,
            maxResults: maxResults
        )
    }

    // MARK: - User Operations
    public func fetchCurrentUser() async throws -> XUser {
        if isMockSession {
            return MockDataProvider.shared.currentUser
        }
        guard !token.isEmpty else {
            throw XKitError.httpError(statusCode: 401, data: nil)
        }
        let user = try await users.me(token: token)
        self.currentUserId = user.id
        self.userCache[user.id] = user
        return user
    }

    public func fetchUserProfile(id: String) async throws -> XUser {
        if let cached = userCache[id] {
            return cached
        }

        let session = SessionManager.shared.currentState
        if case .guest(let guest) = session, !guest.guestToken.isEmpty {
            if let user = try? await graphql.fetchUserByScreenName(screenName: id, guestToken: guest.guestToken) {
                userCache[id] = user
                userCache[user.id] = user
                userCache[user.username] = user
                return user
            }
        } else if case .authenticated(let account) = session, account.authType == .webSession, let csrf = account.csrfToken {
            // 1. If looking up numeric id or current user, try UserByRestId directly
            let targetNumericId = (id == account.username || id == account.id || id.isEmpty) ? account.id : id
            if !targetNumericId.isEmpty && !targetNumericId.starts(with: "user_") && CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: targetNumericId)) {
                if let user = try? await graphql.fetchUserByRestId(
                    userId: targetNumericId,
                    authToken: account.token,
                    csrfToken: csrf,
                    rawCookies: account.rawCookieHeader
                ), !user.username.isEmpty {
                    userCache[id] = user
                    userCache[user.id] = user
                    userCache[user.username] = user
                    if targetNumericId == account.id && (account.username == "x_user" || account.displayName == "Not Me" || account.username != user.username) {
                        await MainActor.run {
                            SessionManager.shared.updateActiveAccount(
                                username: user.username,
                                displayName: user.name,
                                avatarURL: user.profileImageUrl.flatMap(URL.init)
                            )
                        }
                    }
                    return user
                }
            }

            // 2. If looking up current user, verify credentials directly from X
            if id == account.username || id == account.id || id.isEmpty {
                if let user = try? await graphql.verifyCredentials(
                    authToken: account.token,
                    csrfToken: csrf,
                    userId: account.id,
                    rawCookies: account.rawCookieHeader
                ), !user.username.isEmpty {
                    userCache[id] = user
                    userCache[user.id] = user
                    userCache[user.username] = user
                    if account.username == "x_user" || account.displayName == "Not Me" || account.username != user.username {
                        await MainActor.run {
                            SessionManager.shared.updateActiveAccount(
                                username: user.username,
                                displayName: user.name,
                                avatarURL: user.profileImageUrl.flatMap(URL.init)
                            )
                        }
                    }
                    return user
                }
            }

            // 3. Fetch by screen name
            let targetScreenName = (id == account.id || id.isEmpty) ? account.username : id
            if !targetScreenName.isEmpty && targetScreenName != "x_user" {
                if let user = try? await graphql.fetchUserByScreenName(screenName: targetScreenName, authToken: account.token, csrfToken: csrf) {
                    userCache[id] = user
                    userCache[user.id] = user
                    userCache[user.username] = user
                    return user
                }
            }

            // 4. Fallback to active account's known authentic data if matching
            if id == account.username || id == account.id || id.isEmpty {
                let user = XUser(
                    id: account.id,
                    name: account.displayName,
                    username: account.username,
                    description: nil,
                    verified: false,
                    profileImageUrl: account.avatarURL?.absoluteString
                )
                userCache[id] = user
                userCache[user.id] = user
                userCache[user.username] = user
                return user
            }
        }

        do {
            let user = try await users.lookup(id: id, token: token)
            userCache[id] = user
            userCache[user.id] = user
            userCache[user.username] = user
            return user
        } catch {
            if isMockSession {
                if let mockUser = MockDataProvider.shared.users[id] {
                    return mockUser
                }
                if id == currentUserId {
                    return MockDataProvider.shared.currentUser
                }
            }
            if case .authenticated(let account) = session, (id == account.username || id == account.id || id.isEmpty) {
                return XUser(
                    id: account.id,
                    name: account.displayName,
                    username: account.username,
                    description: nil,
                    verified: false,
                    profileImageUrl: account.avatarURL?.absoluteString
                )
            }
            throw error
        }
    }

    // MARK: - Post Operations
    public func createPost(text: String) async throws -> XPost {
        let session = SessionManager.shared.currentState
        if case .authenticated(let account) = session, account.authType == .webSession, let csrf = account.csrfToken {
            do {
                let livePost = try await graphql.createTweet(text: text, authToken: account.token, csrfToken: csrf)
                return livePost
            } catch {
                if isMockSession {
                    return try await posts.create(text: text, token: token)
                }
                throw error
            }
        }
        return try await posts.create(text: text, token: token)
    }

    public func deletePost(id: String) async throws -> Bool {
        return try await posts.delete(id: id, token: token)
    }

    // MARK: - Bookmark Operations
    public func bookmarkPost(id: String) async throws -> Bool {
        return try await bookmarks.add(userId: currentUserId, postId: id, token: token)
    }

    public func removeBookmark(id: String) async throws -> Bool {
        return try await bookmarks.remove(userId: currentUserId, postId: id, token: token)
    }

    public func fetchBookmarks(paginationToken: String? = nil, maxResults: Int = 20) async throws -> PaginatedResponse<XPost> {
        return try await bookmarks.list(
            userId: currentUserId,
            token: token,
            paginationToken: paginationToken,
            maxResults: maxResults
        )
    }

    // MARK: - Post Detail & Thread Operations
    private func detailResult(_ timeline: GraphQLTimelineParser.ParsedTimeline, postId: String) throws -> (post: XPost, replies: [XPost]) {
        guard let post = timeline.posts.first(where: { $0.id == postId }) else {
            throw XKitError.apiError(title: "Post unavailable", detail: "X did not return the requested post.", type: nil)
        }
        for (id, user) in timeline.users { userCache[id] = user }
        // A conversation ID identifies the root, not necessarily a direct reply.
        // Only expose entries attributable to the requested root.
        let replies = timeline.posts.filter { $0.id != postId && $0.conversationId == postId }
        return (post, replies)
    }

    public func fetchPostDetail(postId: String) async throws -> (post: XPost, replies: [XPost]) {
        let session = SessionManager.shared.currentState
        switch session {
        case .guest(let guestSession):
            if !guestSession.guestToken.isEmpty {
                do {
                    let parsed = try await graphql.fetchTweetDetailParsed(tweetId: postId, guestToken: guestSession.guestToken)
                    return try detailResult(parsed, postId: postId)
                } catch {
                    if !isMockSession { throw error }
                }
            }
        case .authenticated(let account):
            if account.authType == .webSession, let csrf = account.csrfToken {
                do {
                    let parsed = try await graphql.fetchTweetDetailParsed(tweetId: postId, authToken: account.token, csrfToken: csrf)
                    return try detailResult(parsed, postId: postId)
                } catch {
                    if !isMockSession { throw error }
                }
            }
        case .unauthenticated:
            break
        }

        // Mock fallback strictly for local unit testing
        if isMockSession {
            if let existing = MockDataProvider.shared.postItems.first(where: { $0.id == postId }) {
                let replies = MockDataProvider.shared.postItems
                    .filter { $0.conversationId == postId && $0.id != postId }
                    .map(\.asXPost)
                return (post: existing.asXPost, replies: replies)
            }
            let fallback = XPost(id: postId, text: "Post #\(postId)", authorId: currentUserId, createdAt: Date(), conversationId: postId)
            return (post: fallback, replies: [])
        }

        throw XKitError.apiError(title: "Not Found", detail: "Post \(postId) not found", type: nil)
    }

    // MARK: - Search Operations
    public func searchPosts(query: String, cursor: String? = nil, maxResults: Int = 20) async throws -> PaginatedResponse<XPost> {
        let session = SessionManager.shared.currentState
        switch session {
        case .guest(let guest):
            if !guest.guestToken.isEmpty {
                do {
                    let parsed = try await graphql.fetchSearchTimelineParsed(
                        query: query,
                        guestToken: guest.guestToken,
                        count: maxResults,
                        cursor: cursor
                    )
                    for (userId, user) in parsed.users {
                        self.userCache[userId] = user
                    }
                    if !parsed.posts.isEmpty {
                        return parsed.asPaginatedResponse
                    }
                } catch {
                    if !isMockSession { throw error }
                }
            }
        case .authenticated(let account):
            if account.authType == .webSession, let csrf = account.csrfToken {
                do {
                    let parsed = try await graphql.fetchSearchTimelineParsed(
                        query: query,
                        authToken: account.token,
                        csrfToken: csrf,
                        count: maxResults,
                        cursor: cursor
                    )
                    for (userId, user) in parsed.users {
                        self.userCache[userId] = user
                    }
                    if !parsed.posts.isEmpty {
                        return parsed.asPaginatedResponse
                    }
                } catch {
                    if !isMockSession { throw error }
                }
            }
        case .unauthenticated:
            break
        }

        if isMockSession {
            let allPosts = MockDataProvider.shared.timelinePosts
            let matching = allPosts.filter { $0.text.localizedCaseInsensitiveContains(query) }
            return PaginatedResponse(data: matching, resultCount: matching.count, nextToken: nil)
        }

        return PaginatedResponse(data: [], resultCount: 0, nextToken: nil)
    }
}

/// Fast, in-memory mock service conforming to XClientServiceProtocol.
@MainActor
public final class MockClientService: XClientServiceProtocol, Sendable {
    private static var idCounter: UInt64 = 0

    public var timelinePosts: [XPost] = []
    public var users: [String: XUser] = [:]
    public var bookmarkedPostIds: Set<String> = []
    public var currentUser: XUser
    public var createdPosts: [XPost] = []
    public var deletedPostIds: Set<String> = []
    public var shouldThrowError: Error?

    @MainActor
    public init(
        currentUser: XUser,
        timelinePosts: [XPost],
        users: [String: XUser]
    ) {
        self.currentUser = currentUser
        self.timelinePosts = timelinePosts
        self.users = users
        self.bookmarkedPostIds = Set(MockDataProvider.shared.bookmarks.map(\.id))
    }

    @MainActor
    public init() {
        self.currentUser = MockDataProvider.shared.currentUser
        self.timelinePosts = MockDataProvider.shared.timelinePosts
        self.users = MockDataProvider.shared.users
        self.bookmarkedPostIds = Set(MockDataProvider.shared.bookmarks.map(\.id))
    }

    @MainActor
    public convenience init(
        timelinePosts: [XPost]
    ) {
        self.init(
            currentUser: MockDataProvider.shared.currentUser,
            timelinePosts: timelinePosts,
            users: MockDataProvider.shared.users
        )
    }

    public func fetchPostDetail(postId: String) async throws -> (post: XPost, replies: [XPost]) {
        try checkError()
        guard let post = timelinePosts.first(where: { $0.id == postId }) else {
            throw XKitError.apiError(title: "Not Found", detail: "Post not found", type: nil)
        }
        return (post, timelinePosts.filter { $0.conversationId == postId && $0.id != postId })
    }

    public func searchPosts(query: String, cursor: String? = nil, maxResults: Int = 20) async throws -> PaginatedResponse<XPost> {
        try checkError()
        let matching = timelinePosts.filter { $0.text.localizedCaseInsensitiveContains(query) }
        let limit = max(0, maxResults)
        let page = Array(matching.prefix(limit))
        return PaginatedResponse(data: page, resultCount: page.count, nextToken: nil)
    }

    private func checkError() throws {
        if let error = shouldThrowError {
            throw error
        }
    }

    public func fetchHomeTimeline() async throws -> [XPost] {
        try checkError()
        return timelinePosts
    }

    public func fetchHomeTimeline(paginationToken: String?, maxResults: Int) async throws -> PaginatedResponse<XPost> {
        try checkError()
        let safeLimit = max(0, maxResults)
        let startIndex: Int
        if let token = paginationToken,
           let offset = Int(token.replacingOccurrences(of: "cursor_mock_", with: "").replacingOccurrences(of: "cursor_", with: "").replacingOccurrences(of: "next_cursor_", with: "")) {
            startIndex = min(max(0, offset), timelinePosts.count)
        } else {
            startIndex = 0
        }
        let endIndex = min(startIndex + safeLimit, timelinePosts.count)
        let slice = Array(timelinePosts[startIndex..<endIndex])
        let nextToken = endIndex < timelinePosts.count ? "cursor_mock_\(endIndex)" : nil
        return PaginatedResponse(data: slice, resultCount: timelinePosts.count, nextToken: nextToken)
    }

    public func fetchUserProfile(id: String) async throws -> XUser {
        try checkError()
        if let user = users[id] {
            return user
        }
        if id == currentUser.id {
            return currentUser
        }
        throw XKitError.apiError(title: "Not Found", detail: "User \(id) not found", type: nil)
    }

    public func fetchUserPosts(userId: String, paginationToken: String?, maxResults: Int) async throws -> PaginatedResponse<XPost> {
        try checkError()
        let safeLimit = max(0, maxResults)
        let userTimeline = timelinePosts.filter { $0.authorId == userId }
        let startIndex: Int
        if let token = paginationToken,
           let offset = Int(token.replacingOccurrences(of: "cursor_mock_", with: "").replacingOccurrences(of: "cursor_", with: "")) {
            startIndex = min(max(0, offset), userTimeline.count)
        } else {
            startIndex = 0
        }
        let endIndex = min(startIndex + safeLimit, userTimeline.count)
        let slice = Array(userTimeline[startIndex..<endIndex])
        let nextToken = endIndex < userTimeline.count ? "cursor_mock_\(endIndex)" : nil
        return PaginatedResponse(data: slice, resultCount: userTimeline.count, nextToken: nextToken)
    }

    public func createPost(text: String) async throws -> XPost {
        try checkError()
        Self.idCounter += 1
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let uuidSuffix = UUID().uuidString.prefix(8).lowercased()
        let uniqueId = "post_mock_\(timestamp)_\(Self.idCounter)_\(uuidSuffix)"
        let newPost = XPost(
            id: uniqueId,
            text: text,
            authorId: currentUser.id,
            createdAt: Date(),
            conversationId: uniqueId
        )
        createdPosts.append(newPost)
        timelinePosts.insert(newPost, at: 0)
        return newPost
    }

    public func deletePost(id: String) async throws -> Bool {
        try checkError()
        deletedPostIds.insert(id)
        let found = timelinePosts.contains { $0.id == id } || createdPosts.contains { $0.id == id }
        if let idx = timelinePosts.firstIndex(where: { $0.id == id }) {
            timelinePosts.remove(at: idx)
        }
        bookmarkedPostIds.remove(id)
        if let createdIdx = createdPosts.firstIndex(where: { $0.id == id }) {
            createdPosts.remove(at: createdIdx)
        }
        return found
    }

    public func bookmarkPost(id: String) async throws -> Bool {
        try checkError()
        bookmarkedPostIds.insert(id)
        return true
    }

    public func removeBookmark(id: String) async throws -> Bool {
        try checkError()
        bookmarkedPostIds.remove(id)
        return true
    }

    public func fetchBookmarks(paginationToken: String?, maxResults: Int) async throws -> PaginatedResponse<XPost> {
        try checkError()
        let safeLimit = max(0, maxResults)
        let bookmarked = timelinePosts.filter { bookmarkedPostIds.contains($0.id) }
        let startIndex: Int
        if let token = paginationToken,
           let offset = Int(token.replacingOccurrences(of: "cursor_mock_", with: "").replacingOccurrences(of: "cursor_", with: "")) {
            startIndex = min(max(0, offset), bookmarked.count)
        } else {
            startIndex = 0
        }
        let endIndex = min(startIndex + safeLimit, bookmarked.count)
        let slice = Array(bookmarked[startIndex..<endIndex])
        let nextToken = endIndex < bookmarked.count ? "cursor_mock_\(endIndex)" : nil
        return PaginatedResponse(data: slice, resultCount: bookmarked.count, nextToken: nextToken)
    }

    public func fetchCurrentUser() async throws -> XUser {
        try checkError()
        return currentUser
    }
}
