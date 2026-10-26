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
    public let transport: HTTPTransport

    // MARK: - Active Session State
    public private(set) var token: String
    public private(set) var currentUserId: String

    // MARK: - Initializers

    /// Initializes with individual services, token, and currentUserId.
    public init(
        users: UsersService,
        posts: PostsService,
        timelines: TimelinesService,
        bookmarks: BookmarksService,
        transport: HTTPTransport,
        token: String = "mock_token",
        currentUserId: String = "usr_me_001"
    ) {
        self.users = users
        self.posts = posts
        self.timelines = timelines
        self.bookmarks = bookmarks
        self.transport = transport
        self.token = token
        self.currentUserId = currentUserId
    }

    /// Convenience initializer wrapping an XKit.XClient facade.
    public convenience init(
        client: XKit.XClient,
        token: String = "mock_token",
        currentUserId: String = "usr_me_001"
    ) {
        self.init(
            users: client.users,
            posts: client.posts,
            timelines: client.timelines,
            bookmarks: client.bookmarks,
            transport: client.transport,
            token: token,
            currentUserId: currentUserId
        )
    }

    /// Default initializer automatically wired to MockDataProvider for zero-credential preview and testing.
    public convenience init() {
        let mockClient = MockDataProvider.makeMockClient()
        self.init(
            client: mockClient,
            token: "mock_token",
            currentUserId: MockDataProvider.shared.currentUser.id
        )
    }

    // MARK: - Session Management
    public func updateCredentials(token: String, currentUserId: String) {
        self.token = token
        self.currentUserId = currentUserId
    }

    // MARK: - Timeline Operations
    public func fetchHomeTimeline() async throws -> [XPost] {
        let response = try await fetchHomeTimeline(paginationToken: nil, maxResults: 20)
        return response.data
    }

    public func fetchHomeTimeline(paginationToken: String?, maxResults: Int) async throws -> PaginatedResponse<XPost> {
        return try await timelines.reverseChronologicalHome(
            userId: currentUserId,
            token: token,
            paginationToken: paginationToken,
            maxResults: maxResults
        )
    }

    public func fetchUserPosts(userId: String, paginationToken: String? = nil, maxResults: Int = 20) async throws -> PaginatedResponse<XPost> {
        return try await timelines.userTweets(
            userId: userId,
            token: token,
            paginationToken: paginationToken,
            maxResults: maxResults
        )
    }

    // MARK: - User Operations
    public func fetchCurrentUser() async throws -> XUser {
        let user = try await users.me(token: token)
        self.currentUserId = user.id
        return user
    }

    public func fetchUserProfile(id: String) async throws -> XUser {
        return try await users.lookup(id: id, token: token)
    }

    // MARK: - Post Operations
    public func createPost(text: String) async throws -> XPost {
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

    public init(
        currentUser: XUser = MockDataProvider.shared.currentUser,
        timelinePosts: [XPost] = MockDataProvider.shared.timelinePosts,
        users: [String: XUser] = MockDataProvider.shared.users
    ) {
        self.currentUser = currentUser
        self.timelinePosts = timelinePosts
        self.users = users
        self.bookmarkedPostIds = Set(MockDataProvider.shared.bookmarks.map(\.id))
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
