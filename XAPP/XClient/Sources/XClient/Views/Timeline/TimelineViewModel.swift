//
//  TimelineViewModel.swift
//  XClient
//
//  MainActor ViewModel managing reverse-chronological timeline posts,
//  pull-to-refresh, background polling unread buffer, and social action mutations.
//  100% Swift 6 strict concurrency compliance.
//

import SwiftUI
import Combine
import XKitModels

/// MainActor coordinator managing timeline feed state, unread buffer, and background polling.
@MainActor
public final class TimelineViewModel: ObservableObject, Sendable {
    // MARK: - Published Feed State
    @Published public var posts: [PostItem] = []
    @Published public private(set) var unreadBuffer: [PostItem] = []
    @Published public private(set) var unreadCount: Int = 0
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isRefreshing: Bool = false
    @Published public private(set) var isLoadingMore: Bool = false
    @Published public private(set) var errorMessage: String? = nil
    @Published public private(set) var nextPaginationToken: String? = nil
    @Published public private(set) var isPollingActive: Bool = false
    @Published public var isShowingSearchSheet: Bool = false

    // MARK: - Preferences & Configuration
    @Published public var autoRefreshInterval: TimeInterval = 30.0 {
        didSet {
            Task {
                await pollingEngine.updateInterval(autoRefreshInterval)
            }
        }
    }

    // MARK: - Injected Dependencies
    public let service: any XClientServiceProtocol
    public let pollingEngine: TimelinePollingEngine
    private weak var navigationState: AppNavigationState?
    private var pendingActions: Set<String> = []

    // MARK: - Initialization
    @MainActor
    public init(
        service: (any XClientServiceProtocol)? = nil,
        pollingEngine: TimelinePollingEngine? = nil,
        navigationState: AppNavigationState? = nil,
        autoRefreshInterval: TimeInterval = 30.0
    ) {
        let resolvedService = service ?? XClientService()
        self.service = resolvedService
        self.pollingEngine = pollingEngine ?? TimelinePollingEngine(interval: autoRefreshInterval, service: resolvedService)
        self.navigationState = navigationState
        self.autoRefreshInterval = autoRefreshInterval
    }

    public func attach(navigationState: AppNavigationState) {
        self.navigationState = navigationState
    }

    // MARK: - Feed Loading Actions

    /// Initial load of the reverse-chronological timeline.
    public func fetchTimeline() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let response = try await service.fetchHomeTimeline(paginationToken: nil, maxResults: 20)
            var map: [String: PostItem] = [:]
            for post in response.data.map({ makePostItem(from: $0) }) {
                map[post.id] = post
            }
            let domainItems = Array(map.values).sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.id > $1.id
                }
                return $0.createdAt > $1.createdAt
            }
            self.posts = domainItems
            self.nextPaginationToken = response.nextToken

            // Register known IDs with background polling engine
            let ids = domainItems.map(\.id)
            await pollingEngine.recordKnownPostIds(ids)

            // Start polling engine if not already started
            await startPollingEngine()
            isLoading = false
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }

    /// Pull-to-refresh execution. Flushes unread buffer and prepends latest top posts without duplication.
    public func refreshTimeline() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil

        do {
            let response = try await service.fetchHomeTimeline(paginationToken: nil, maxResults: 20)
            let fetchedItems = response.data.map { makePostItem(from: $0) }

            // Strict unique deduplication by post ID across existing, buffer, and newly fetched
            var map: [String: PostItem] = [:]
            for post in self.posts {
                map[post.id] = post
            }
            for post in self.unreadBuffer {
                map[post.id] = post
            }
            for post in fetchedItems {
                map[post.id] = post
            }

            let sorted = Array(map.values).sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.id > $1.id
                }
                return $0.createdAt > $1.createdAt
            }

            self.posts = sorted
            self.unreadBuffer = []
            self.unreadCount = 0
            navigationState?.clearBadge(for: .timeline)

            if let token = response.nextToken, self.nextPaginationToken == nil {
                self.nextPaginationToken = token
            }

            await pollingEngine.recordKnownPostIds(sorted.map(\.id))
            self.isRefreshing = false
        } catch {
            self.errorMessage = error.localizedDescription
            self.isRefreshing = false
        }
    }

    /// Infinite scrolling pagination for older posts.
    public func loadMore() async {
        guard !isLoadingMore, let token = nextPaginationToken, !token.isEmpty else { return }
        isLoadingMore = true

        do {
            let response = try await service.fetchHomeTimeline(paginationToken: token, maxResults: 20)
            let olderItems = response.data.map { makePostItem(from: $0) }

            // Deduplicate on append
            let existingIds = Set(posts.map(\.id))
            let uniqueOlder = olderItems.filter { !existingIds.contains($0.id) }
            self.posts.append(contentsOf: uniqueOlder)
            self.nextPaginationToken = response.nextToken

            await pollingEngine.recordKnownPostIds(uniqueOlder.map(\.id))
            self.isLoadingMore = false
        } catch {
            self.isLoadingMore = false
        }
    }

    // MARK: - Unread Buffer Management

    /// Flushes all unread buffered posts directly into the top of the visible feed in strict reverse-chronological order.
    public func flushUnreadBuffer() {
        guard !unreadBuffer.isEmpty else { return }
        let buffered = unreadBuffer
        unreadBuffer = []
        unreadCount = 0
        navigationState?.clearBadge(for: .timeline)

        // Prepend unread posts avoiding duplicates and maintaining strict reverse-chronological order
        let existingIds = Set(posts.map(\.id))
        var seen = Set<String>()
        let uniqueBuffered = buffered
            .filter { !existingIds.contains($0.id) && seen.insert($0.id).inserted }
            .sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.id > $1.id
                }
                return $0.createdAt > $1.createdAt
            }
        self.posts = uniqueBuffered + posts
    }

    /// Callback handler invoked when PollingEngine discovers new posts.
    /// Filters both existing and intra-batch duplicates and maintains unreadBuffer in strict reverse-chronological order.
    public func handleNewPolledPosts(_ newWirePosts: [XPost]) {
        let existingIds = Set(posts.map(\.id)).union(Set(unreadBuffer.map(\.id)))
        var seenWireIds = Set<String>()
        let novelWirePosts = newWirePosts.filter { post in
            !existingIds.contains(post.id) && seenWireIds.insert(post.id).inserted
        }
        guard !novelWirePosts.isEmpty else { return }

        let newDomainItems = novelWirePosts.map { makePostItem(from: $0) }
        // Prepend to unread buffer preserving reverse-chronological order
        self.unreadBuffer = (newDomainItems + unreadBuffer).sorted {
            if $0.createdAt == $1.createdAt {
                return $0.id > $1.id
            }
            return $0.createdAt > $1.createdAt
        }
        self.unreadCount = unreadBuffer.count

        // Update tab badge in navigation state
        navigationState?.setBadgeCount(self.unreadCount, for: .timeline)
    }

    // MARK: - Optimistic Social Actions

    /// Apply optimistic changes only while a single request for the action is in flight.
    public func toggleLike(for post: PostItem) {
        let key = "like:" + post.id
        guard !pendingActions.contains(key), let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        let previous = posts[index].isLiked
        let previousCount = posts[index].likeCount
        let desired = !previous
        pendingActions.insert(key)
        posts[index].isLiked = desired
        posts[index].likeCount = max(0, previousCount + (desired ? 1 : -1))
        Task {
            defer { pendingActions.remove(key) }
            do {
                if service is MockClientService {
                    MockDataProvider.shared.toggleLike(postId: post.id, forceState: desired)
                } else if let concrete = service as? XClientService, let csrf = concrete.csrfToken, !csrf.isEmpty {
                    let success = try await (desired
                        ? concrete.graphql.likeTweet(tweetId: post.id, authToken: concrete.token, csrfToken: csrf)
                        : concrete.graphql.unlikeTweet(tweetId: post.id, authToken: concrete.token, csrfToken: csrf))
                    guard success else { throw XKitError.apiError(title: "Like failed", detail: "X did not accept this action.", type: nil) }
                } else {
                    throw XKitError.apiError(title: "Like unavailable", detail: "Sign in to like posts.", type: nil)
                }
            } catch {
                if let i = posts.firstIndex(where: { $0.id == post.id }) {
                    posts[i].isLiked = previous
                    posts[i].likeCount = previousCount
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    public func toggleBookmark(for post: PostItem) {
        let key = "bookmark:" + post.id
        guard !pendingActions.contains(key), let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        let previous = posts[index].isBookmarked
        let previousCount = posts[index].bookmarkCount
        let desired = !previous
        pendingActions.insert(key)
        posts[index].isBookmarked = desired
        posts[index].bookmarkCount = max(0, previousCount + (desired ? 1 : -1))
        Task {
            defer { pendingActions.remove(key) }
            do {
                let success = try await (desired ? service.bookmarkPost(id: post.id) : service.removeBookmark(id: post.id))
                guard success else { throw XKitError.apiError(title: "Bookmark failed", detail: "X did not accept this action.", type: nil) }
            } catch {
                if let i = posts.firstIndex(where: { $0.id == post.id }) {
                    posts[i].isBookmarked = previous
                    posts[i].bookmarkCount = previousCount
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    public func toggleRepost(for post: PostItem) {
        let key = "repost:" + post.id
        guard !pendingActions.contains(key), let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        let previous = posts[index].isReposted
        let previousCount = posts[index].repostCount
        // The available endpoint creates reposts; it cannot undo one.
        if previous && !(service is MockClientService) {
            errorMessage = "Removing a repost is not available yet."
            return
        }
        pendingActions.insert(key)
        posts[index].isReposted = !previous
        posts[index].repostCount = max(0, previousCount + (previous ? -1 : 1))
        Task {
            defer { pendingActions.remove(key) }
            do {
                if service is MockClientService {
                    MockDataProvider.shared.toggleRepost(postId: post.id)
                } else if let concrete = service as? XClientService, let csrf = concrete.csrfToken, !csrf.isEmpty {
                    guard try await concrete.graphql.retweet(tweetId: post.id, authToken: concrete.token, csrfToken: csrf) else {
                        throw XKitError.apiError(title: "Repost failed", detail: "X did not accept this action.", type: nil)
                    }
                } else {
                    throw XKitError.apiError(title: "Repost unavailable", detail: "Sign in to repost.", type: nil)
                }
            } catch {
                if let i = posts.firstIndex(where: { $0.id == post.id }) {
                    posts[i].isReposted = previous
                    posts[i].repostCount = previousCount
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    public func deletePost(_ post: PostItem) {
        let key = "delete:" + post.id
        guard !pendingActions.contains(key) else { return }
        pendingActions.insert(key)
        // Keep the row visible until the server confirms the deletion.
        Task {
            defer { pendingActions.remove(key) }
            do {
                guard try await service.deletePost(id: post.id) else {
                    throw XKitError.apiError(title: "Delete failed", detail: "X did not accept this action.", type: nil)
                }
                posts.removeAll { $0.id == post.id }
                unreadBuffer.removeAll { $0.id == post.id }
                unreadCount = unreadBuffer.count
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Lifecycle Management

    public func onAppear() {
        if posts.isEmpty && !isLoading {
            Task { await fetchTimeline() }
        } else {
            Task { await resumePolling() }
        }
    }

    public func onDisappear() {
        Task { await pausePolling() }
    }

    public func pausePolling() async {
        await pollingEngine.pause()
        isPollingActive = false
    }

    public func resumePolling() async {
        guard autoRefreshInterval > 0 else { return }
        await pollingEngine.resume()
        isPollingActive = true
    }

    // MARK: - Internal Helpers
    private func startPollingEngine() async {
        let currentKnownIds = (posts + unreadBuffer).map(\.id)
        let currentService = self.service
        await pollingEngine.startPolling(
            interval: autoRefreshInterval,
            initialKnownIds: currentKnownIds,
            fetchHandler: {
                let response = try await currentService.fetchHomeTimeline(paginationToken: nil, maxResults: 10)
                return response.data
            },
            onNewPosts: { [weak self] newPosts in
                await MainActor.run {
                    self?.handleNewPolledPosts(newPosts)
                }
            },
            onError: { [weak self] error in
                await MainActor.run {
                    self?.errorMessage = error.localizedDescription
                }
            }
        )
        isPollingActive = (autoRefreshInterval > 0)
    }

    private func makePostItem(from xPost: XPost) -> PostItem {
        let authorId = xPost.authorId ?? "usr_unknown"
        let resolvedAuthor: XUser
        if let concreteService = service as? XClientService, let cached = concreteService.userCache[authorId] {
            resolvedAuthor = cached
        } else if let mockService = service as? MockClientService, let cached = mockService.users[authorId] {
            resolvedAuthor = cached
        } else {
            resolvedAuthor = XUser(
                id: authorId,
                name: authorId.hasPrefix("usr_") ? "User" : "@\(authorId)",
                username: authorId.hasPrefix("usr_") ? "user" : authorId
            )
        }

        var item = PostItem(post: xPost, author: resolvedAuthor)
        if let mockService = service as? MockClientService {
            item.isBookmarked = mockService.bookmarkedPostIds.contains(xPost.id)
        }
        return item
    }
}
