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
            let domainItems = response.data
                .map { makePostItem(from: $0) }
                .sorted { $0.createdAt > $1.createdAt }
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

    /// Pull-to-refresh execution. Flushes unread buffer and prepends latest top posts.
    public func refreshTimeline() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil

        do {
            let response = try await service.fetchHomeTimeline(paginationToken: nil, maxResults: 20)
            let fetchedItems = response.data.map { makePostItem(from: $0) }

            // 1. Flush any pending unread buffer items maintaining strict reverse-chronological order
            let existingIds = Set(posts.map(\.id))
            var seenBuffered = Set<String>()
            let uniqueBuffered = unreadBuffer
                .filter { !existingIds.contains($0.id) && seenBuffered.insert($0.id).inserted }
                .sorted {
                    if $0.createdAt == $1.createdAt {
                        return $0.id > $1.id
                    }
                    return $0.createdAt > $1.createdAt
                }
            var updatedPosts = uniqueBuffered + posts
            unreadBuffer = []
            unreadCount = 0
            navigationState?.clearBadge(for: .timeline)

            // 2. Prepend newly fetched posts that are not already present, filtering intra-batch duplicates
            let currentIds = Set(updatedPosts.map(\.id))
            var seenFetched = Set<String>()
            let novelItems = fetchedItems
                .filter { !currentIds.contains($0.id) && seenFetched.insert($0.id).inserted }
                .sorted {
                    if $0.createdAt == $1.createdAt {
                        return $0.id > $1.id
                    }
                    return $0.createdAt > $1.createdAt
                }
            updatedPosts = novelItems + updatedPosts

            self.posts = updatedPosts
            if let token = response.nextToken, self.nextPaginationToken == nil {
                self.nextPaginationToken = token
            }

            // Record all known IDs
            await pollingEngine.recordKnownPostIds(updatedPosts.map(\.id))
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

    /// Toggles like state optimistically and synchronizes with live X service or mock test harness.
    public func toggleLike(for post: PostItem) {
        let targetId = post.id
        guard let index = posts.firstIndex(where: { $0.id == targetId }) else { return }

        let currentState = posts[index].isLiked
        let newState = !currentState
        posts[index].isLiked = newState
        posts[index].likeCount = max(0, posts[index].likeCount + (newState ? 1 : -1))

        if service is MockClientService {
            MockDataProvider.shared.toggleLike(postId: targetId, forceState: newState)
        } else if let concreteService = service as? XClientService, let csrf = concreteService.csrfToken {
            Task {
                if newState {
                    _ = try? await concreteService.graphql.likeTweet(
                        tweetId: targetId,
                        authToken: concreteService.token,
                        csrfToken: csrf
                    )
                } else {
                    _ = try? await concreteService.graphql.unlikeTweet(
                        tweetId: targetId,
                        authToken: concreteService.token,
                        csrfToken: csrf
                    )
                }
            }
        }
    }

    /// Toggles bookmark state optimistically and invokes service mutation.
    public func toggleBookmark(for post: PostItem) {
        let targetId = post.id
        guard let index = posts.firstIndex(where: { $0.id == targetId }) else { return }

        let currentState = posts[index].isBookmarked
        let newState = !currentState
        posts[index].isBookmarked = newState
        posts[index].bookmarkCount = max(0, posts[index].bookmarkCount + (newState ? 1 : -1))

        if service is MockClientService {
            MockDataProvider.shared.toggleBookmark(postId: targetId, forceState: newState)
        }

        // Asynchronous service dispatch with rollback on error
        Task {
            do {
                if newState {
                    _ = try await service.bookmarkPost(id: targetId)
                } else {
                    _ = try await service.removeBookmark(id: targetId)
                }
            } catch {
                // Revert optimistic mutation
                if let revertIdx = self.posts.firstIndex(where: { $0.id == targetId }) {
                    self.posts[revertIdx].isBookmarked = currentState
                    self.posts[revertIdx].bookmarkCount = max(0, self.posts[revertIdx].bookmarkCount + (currentState ? 1 : -1))
                }
            }
        }
    }

    /// Toggles repost state optimistically and notifies service.
    public func toggleRepost(for post: PostItem) {
        let targetId = post.id
        guard let index = posts.firstIndex(where: { $0.id == targetId }) else { return }

        let currentState = posts[index].isReposted
        let newState = !currentState
        posts[index].isReposted = newState
        posts[index].repostCount = max(0, posts[index].repostCount + (newState ? 1 : -1))

        if service is MockClientService {
            MockDataProvider.shared.toggleRepost(postId: targetId)
        } else if let concreteService = service as? XClientService, let csrf = concreteService.csrfToken {
            Task {
                _ = try? await concreteService.graphql.retweet(
                    tweetId: targetId,
                    authToken: concreteService.token,
                    csrfToken: csrf
                )
            }
        }
    }

    /// Deletes a post from feed and notifies backend service.
    public func deletePost(_ post: PostItem) {
        let targetId = post.id
        posts.removeAll { $0.id == targetId }
        unreadBuffer.removeAll { $0.id == targetId }
        unreadCount = unreadBuffer.count

        Task {
            _ = try? await service.deletePost(id: targetId)
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
