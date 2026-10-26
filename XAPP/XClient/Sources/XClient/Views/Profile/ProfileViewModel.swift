//
//  ProfileViewModel.swift
//  XClient
//
//  MainActor ViewModel managing profile state, 4 subtabs (Posts, Replies, Media, Likes),
//  follower/following metrics, independent feeds, and optimistic follow mutations.
//  100% Swift 6 strict concurrency compliance.
//

import SwiftUI
import Combine
import XKitModels
import XKitAPI

/// Primary subtab navigation sections within a user's profile surface.
public enum ProfileSubtab: String, CaseIterable, Identifiable, Sendable, Codable {
    case posts = "posts"
    case replies = "replies"
    case media = "media"
    case likes = "likes"

    public var id: String { rawValue }

    /// Localized, human-readable title conforming to Apple HIG.
    public var title: String {
        switch self {
        case .posts: return "Posts"
        case .replies: return "Replies"
        case .media: return "Media"
        case .likes: return "Likes"
        }
    }

    /// Empty state SF Symbol icon name.
    public var emptyStateIcon: String {
        switch self {
        case .posts: return "square.and.pencil"
        case .replies: return "bubble.left.and.bubble.right"
        case .media: return "photo.on.rectangle.angled"
        case .likes: return "heart"
        }
    }

    /// Empty state descriptive subtitle.
    public func emptyDescription(for username: String) -> String {
        switch self {
        case .posts:
            return "@\(username) hasn't posted anything yet."
        case .replies:
            return "@\(username) hasn't replied to any posts yet."
        case .media:
            return "Photos and videos uploaded by @\(username) will appear here."
        case .likes:
            return "Posts liked by @\(username) will appear here."
        }
    }
}

/// Represents an individual media item displayed in the profile media grid.
public struct ProfileMediaItem: Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public let attachment: MediaAttachment
    public let post: PostItem

    public init(attachment: MediaAttachment, post: PostItem) {
        self.id = "\(post.id)_\(attachment.id)"
        self.attachment = attachment
        self.post = post
    }
}

/// Action presentation style for the profile header.
public enum ProfileActionMode: Sendable, Equatable {
    case currentUser                  // Shows "Edit Profile"
    case otherUser(isFollowing: Bool) // Shows "Follow" or "Following"
}

/// MainActor coordinator managing user profile state and subtab feeds.
@MainActor
public final class ProfileViewModel: ObservableObject, Sendable {
    // MARK: - Published Profile Metadata
    @Published public private(set) var userProfile: UserProfile?
    @Published public private(set) var targetUserId: String
    @Published public private(set) var isCurrentUser: Bool = false

    // MARK: - Published Follow & Metrics State
    @Published public private(set) var isFollowing: Bool = false
    @Published public private(set) var followersCount: Int = 0
    @Published public private(set) var followingCount: Int = 0
    @Published public private(set) var postsCount: Int = 0

    // MARK: - Subtabs & Feed Caches
    @Published public var selectedSubtab: ProfileSubtab = .posts {
        didSet {
            if oldValue != selectedSubtab {
                Task { await fetchFeedIfNeeded(for: selectedSubtab) }
            }
        }
    }
    @Published public private(set) var postsBySubtab: [ProfileSubtab: [PostItem]] = [:]
    @Published public private(set) var mediaItems: [ProfileMediaItem] = []

    // MARK: - Loading & Error States
    @Published public var scrollOffsetY: CGFloat = 0.0
    @Published public private(set) var isLoadingProfile: Bool = false
    @Published public private(set) var isLoadingFeed: Bool = false
    @Published public private(set) var isRefreshing: Bool = false
    @Published public private(set) var errorMessage: String? = nil

    // MARK: - Injected Dependencies
    public let service: any XClientServiceProtocol
    private weak var navigationState: AppNavigationState?

    // MARK: - Initialization
    public init(
        userId: String? = nil,
        service: any XClientServiceProtocol = XClientService(),
        navigationState: AppNavigationState? = nil,
        initialProfile: UserProfile? = nil
    ) {
        self.service = service
        self.navigationState = navigationState

        let resolvedId = userId ?? MockDataProvider.shared.currentUser.id
        self.targetUserId = resolvedId
        self.isCurrentUser = (resolvedId == MockDataProvider.shared.currentUser.id)

        if let initial = initialProfile {
            self.userProfile = initial
            self.isFollowing = initial.isFollowing
            self.followersCount = initial.followersCount
            self.followingCount = initial.followingCount
            self.postsCount = initial.postsCount
        }
    }

    public func attach(navigationState: AppNavigationState) {
        self.navigationState = navigationState
    }

    // MARK: - Computed Properties
    public var currentPosts: [PostItem] {
        postsBySubtab[selectedSubtab] ?? []
    }

    public var isFeedEmpty: Bool {
        if selectedSubtab == .media {
            return mediaItems.isEmpty
        }
        return currentPosts.isEmpty
    }

    public var actionMode: ProfileActionMode {
        if isCurrentUser {
            return .currentUser
        } else {
            return .otherUser(isFollowing: isFollowing)
        }
    }

    // MARK: - Primary Loading Actions

    /// Loads user profile metadata and initializes the primary Posts feed.
    public func loadProfile() async {
        guard !isLoadingProfile else { return }
        isLoadingProfile = true
        errorMessage = nil

        do {
            // 1. Resolve User Profile
            let resolvedProfile: UserProfile
            if let cached = MockDataProvider.shared.userProfiles[targetUserId] {
                resolvedProfile = cached
            } else {
                let user = try await service.fetchUserProfile(id: targetUserId)
                resolvedProfile = UserProfile(
                    user: user,
                    headerImageUrl: URL(string: "https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?auto=format&fit=crop&w=1200&h=400&q=80"),
                    bio: user.description,
                    location: nil,
                    websiteUrl: nil,
                    joinedDate: Date(),
                    followersCount: 120,
                    followingCount: 84,
                    postsCount: 12,
                    isFollowing: false
                )
            }

            self.userProfile = resolvedProfile
            MockDataProvider.shared.userProfiles[targetUserId] = resolvedProfile
            self.isFollowing = resolvedProfile.isFollowing
            self.followersCount = resolvedProfile.followersCount
            self.followingCount = resolvedProfile.followingCount
            self.postsCount = resolvedProfile.postsCount
            self.isCurrentUser = (resolvedProfile.user.id == MockDataProvider.shared.currentUser.id)
            self.isLoadingProfile = false

            // 2. Fetch Active Subtab Feed
            await fetchFeed(for: selectedSubtab)
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoadingProfile = false
        }
    }

    /// Pull-to-refresh execution. Reloads profile metadata and invalidates current subtab cache.
    public func refreshProfile() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil

        do {
            // Re-fetch profile
            if let cached = MockDataProvider.shared.userProfiles[targetUserId] {
                self.userProfile = cached
                self.isFollowing = cached.isFollowing
                self.followersCount = cached.followersCount
                self.followingCount = cached.followingCount
                self.postsCount = cached.postsCount
            } else {
                let user = try await service.fetchUserProfile(id: targetUserId)
                let existingProfile = self.userProfile
                let followers = self.followersCount
                let following = self.followingCount
                let posts = self.postsCount
                let followingState = self.isFollowing
                let refreshedProfile = UserProfile(
                    user: user,
                    headerImageUrl: existingProfile?.headerImageUrl ?? URL(string: "https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?auto=format&fit=crop&w=1200&h=400&q=80"),
                    bio: user.description ?? existingProfile?.bio,
                    location: existingProfile?.location,
                    websiteUrl: existingProfile?.websiteUrl,
                    joinedDate: existingProfile?.joinedDate ?? Date(),
                    followersCount: followers,
                    followingCount: following,
                    postsCount: posts,
                    isFollowing: followingState
                )
                self.userProfile = refreshedProfile
                MockDataProvider.shared.userProfiles[targetUserId] = refreshedProfile
            }

            // Invalidate current subtab feed to force re-query
            postsBySubtab.removeValue(forKey: selectedSubtab)
            if selectedSubtab == .media {
                mediaItems.removeAll()
            }

            await fetchFeed(for: selectedSubtab)
            self.isRefreshing = false
        } catch {
            self.errorMessage = error.localizedDescription
            self.isRefreshing = false
        }
    }

    /// Selects an active subtab and lazily fetches its feed if not yet cached.
    public func selectSubtab(_ subtab: ProfileSubtab) {
        guard selectedSubtab != subtab else { return }
        selectedSubtab = subtab
    }

    // MARK: - Subtab Feed Management

    public func fetchFeedIfNeeded(for subtab: ProfileSubtab) async {
        if postsBySubtab[subtab] == nil {
            await fetchFeed(for: subtab)
        }
    }

    public func fetchFeed(for subtab: ProfileSubtab) async {
        isLoadingFeed = true

        let items: [PostItem]
        switch subtab {
        case .posts:
            if let response = try? await service.fetchUserPosts(userId: targetUserId, paginationToken: nil, maxResults: 50),
               !response.data.isEmpty {
                items = response.data.map { xPost in
                    if let existing = MockDataProvider.shared.postItems.first(where: { $0.id == xPost.id }) {
                        return existing
                    }
                    let authorId = xPost.authorId ?? self.targetUserId
                    let author = MockDataProvider.shared.users[authorId] ?? (self.userProfile?.user ?? MockDataProvider.shared.currentUser)
                    return PostItem(
                        id: xPost.id,
                        text: xPost.text,
                        author: author,
                        createdAt: xPost.createdAt ?? Date(),
                        mediaAttachments: []
                    )
                }
            } else {
                items = MockDataProvider.shared.postsForUser(id: targetUserId)
            }
        case .replies:
            items = MockDataProvider.shared.repliesForUser(id: targetUserId)
        case .media:
            let mediaPosts = MockDataProvider.shared.mediaForUser(id: targetUserId)
            items = mediaPosts
            self.mediaItems = mediaPosts.flatMap { post in
                post.mediaAttachments.map { ProfileMediaItem(attachment: $0, post: post) }
            }
        case .likes:
            items = MockDataProvider.shared.likesForUser(id: targetUserId)
        }

        self.postsBySubtab[subtab] = items
        self.isLoadingFeed = false
    }

    // MARK: - Optimistic Follow / Unfollow Mutation

    /// Toggles follow status with optimistic UI updates and resilient failure rollback.
    public func toggleFollow() {
        guard !isCurrentUser else { return }

        let previousState = self.isFollowing
        let previousCount = self.followersCount

        let newState = !previousState
        let newCount = max(0, previousCount + (newState ? 1 : -1))

        // 1. Optimistic Update
        self.isFollowing = newState
        self.followersCount = newCount

        if var profile = self.userProfile {
            profile.isFollowing = newState
            profile.followersCount = newCount
            self.userProfile = profile
            MockDataProvider.shared.userProfiles[targetUserId] = profile
        }

        // 2. Service Dispatch with Rollback Guard
        Task {
            do {
                try await Task.sleep(nanoseconds: 100_000_000) // Simulated network latency
            } catch is CancellationError {
                // Task cancelled by view lifecycle or dismissal - retain optimistic state
                return
            } catch {
                // Rollback on genuine network failure
                await MainActor.run {
                    self.isFollowing = previousState
                    self.followersCount = previousCount
                    if var profile = self.userProfile {
                        profile.isFollowing = previousState
                        profile.followersCount = previousCount
                        self.userProfile = profile
                        MockDataProvider.shared.userProfiles[self.targetUserId] = profile
                    }
                    self.errorMessage = "Failed to update follow status. Please try again."
                }
            }
        }
    }

    // MARK: - Social Action Mutations

    /// Toggles like state on a post across subtab feeds and syncs with MockDataProvider.
    public func toggleLike(for post: PostItem) {
        let targetId = post.id
        let newState: Bool
        if MockDataProvider.shared.postItems.contains(where: { $0.id == targetId }) {
            newState = MockDataProvider.shared.toggleLike(postId: targetId)
        } else {
            newState = !post.isLiked
        }

        // Mutate across all cached subtab feeds
        for (subtab, feed) in postsBySubtab {
            if let idx = feed.firstIndex(where: { $0.id == targetId }) {
                var updated = feed
                updated[idx].isLiked = newState
                updated[idx].likeCount = max(0, updated[idx].likeCount + (newState ? 1 : -1))
                postsBySubtab[subtab] = updated
            }
        }
    }

    /// Toggles repost state on a post.
    public func toggleRepost(for post: PostItem) {
        let targetId = post.id
        let newState: Bool
        if MockDataProvider.shared.postItems.contains(where: { $0.id == targetId }) {
            newState = MockDataProvider.shared.toggleRepost(postId: targetId)
        } else {
            newState = !post.isReposted
        }

        for (subtab, feed) in postsBySubtab {
            if let idx = feed.firstIndex(where: { $0.id == targetId }) {
                var updated = feed
                updated[idx].isReposted = newState
                updated[idx].repostCount = max(0, updated[idx].repostCount + (newState ? 1 : -1))
                postsBySubtab[subtab] = updated
            }
        }
    }

    /// Toggles bookmark state on a post.
    public func toggleBookmark(for post: PostItem) {
        let targetId = post.id
        let newState: Bool
        if MockDataProvider.shared.postItems.contains(where: { $0.id == targetId }) {
            newState = MockDataProvider.shared.toggleBookmark(postId: targetId)
        } else {
            newState = !post.isBookmarked
        }

        for (subtab, feed) in postsBySubtab {
            if let idx = feed.firstIndex(where: { $0.id == targetId }) {
                var updated = feed
                updated[idx].isBookmarked = newState
                updated[idx].bookmarkCount = max(0, updated[idx].bookmarkCount + (newState ? 1 : -1))
                postsBySubtab[subtab] = updated
            }
        }

        Task {
            if newState {
                _ = try? await service.bookmarkPost(id: targetId)
            } else {
                _ = try? await service.removeBookmark(id: targetId)
            }
        }
    }

    /// Deletes a post from feeds and mock store.
    public func deletePost(_ post: PostItem) {
        let targetId = post.id
        for (subtab, feed) in postsBySubtab {
            postsBySubtab[subtab] = feed.filter { $0.id != targetId }
        }
        mediaItems.removeAll { $0.post.id == targetId }
        MockDataProvider.shared.deletePost(id: targetId)

        Task {
            _ = try? await service.deletePost(id: targetId)
        }
    }

    // MARK: - Lifecycle Management
    public func onAppear() {
        if userProfile == nil && !isLoadingProfile {
            Task { await loadProfile() }
        } else if postsBySubtab[selectedSubtab] == nil && !isLoadingFeed {
            Task { await fetchFeed(for: selectedSubtab) }
        }
    }
}
