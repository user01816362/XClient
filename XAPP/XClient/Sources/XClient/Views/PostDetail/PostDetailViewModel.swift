//
//  PostDetailViewModel.swift
//  XClient
//
//  MainActor ViewModel coordinating thread conversation loading,
//  focal post presentation, reply dispatch, and social mutations.
//  100% Swift 6 strict concurrency compliance.
//

import SwiftUI
import Combine
import XKitModels

@MainActor
public final class PostDetailViewModel: ObservableObject, Sendable {
    public let postId: String
    public let service: any XClientServiceProtocol

    @Published public var focalPost: PostItem?
    @Published public var replies: [PostItem] = []
    @Published public var isLoading: Bool = false
    @Published public var isSubmittingReply: Bool = false
    @Published public var replyText: String = ""
    @Published public var errorMessage: String? = nil

    public init(postId: String, service: (any XClientServiceProtocol)? = nil) {
        self.postId = postId
        self.service = service ?? XClientService()
    }

    public func loadPostDetail() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        // If available in local mock store, preload immediately for instant response
        if focalPost == nil, let existing = MockDataProvider.shared.postItems.first(where: { $0.id == postId }) {
            self.focalPost = existing
        }

        do {
            let (postWire, repliesWire) = try await service.fetchPostDetail(postId: postId)

            // Resolve author
            let author = MockDataProvider.shared.users[postWire.authorId ?? ""] ?? XUser(
                id: postWire.authorId ?? "usr_unknown",
                name: "User",
                username: "user"
            )
            var focal = PostItem(post: postWire, author: author)
            focal.isLiked = MockDataProvider.shared.userLikes[MockDataProvider.shared.currentUser.id]?.contains(postId) ?? false
            focal.isBookmarked = MockDataProvider.shared.bookmarks.contains(where: { $0.id == postId })
            self.focalPost = focal

            // Resolve replies
            self.replies = repliesWire.map { replyPost in
                let replyAuthor = MockDataProvider.shared.users[replyPost.authorId ?? ""] ?? XUser(
                    id: replyPost.authorId ?? "usr_unknown",
                    name: "User",
                    username: "user"
                )
                var replyItem = PostItem(post: replyPost, author: replyAuthor)
                replyItem.isLiked = MockDataProvider.shared.userLikes[MockDataProvider.shared.currentUser.id]?.contains(replyPost.id) ?? false
                replyItem.isBookmarked = MockDataProvider.shared.bookmarks.contains(where: { $0.id == replyPost.id })
                return replyItem
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    public func submitReply() async {
        let trimmed = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSubmittingReply else { return }
        isSubmittingReply = true

        do {
            let created = try await service.createPost(text: trimmed)
            let author = MockDataProvider.shared.currentUser
            let replyItem = PostItem(
                id: created.id,
                text: created.text,
                author: author,
                createdAt: Date(),
                conversationId: postId,
                inReplyToPostId: postId
            )

            // Prepend reply and increment reply count
            self.replies.insert(replyItem, at: 0)
            if var post = self.focalPost {
                post.replyCount += 1
                self.focalPost = post
            }
            self.replyText = ""
        } catch {
            self.errorMessage = "Failed to post reply: \(error.localizedDescription)"
        }

        isSubmittingReply = false
    }

    public func toggleLike() {
        guard var post = focalPost else { return }
        let newState = !post.isLiked
        post.isLiked = newState
        post.likeCount = max(0, post.likeCount + (newState ? 1 : -1))
        self.focalPost = post
        MockDataProvider.shared.toggleLike(postId: post.id, forceState: newState)
    }

    public func toggleBookmark() {
        guard var post = focalPost else { return }
        let newState = !post.isBookmarked
        post.isBookmarked = newState
        post.bookmarkCount = max(0, post.bookmarkCount + (newState ? 1 : -1))
        self.focalPost = post
        MockDataProvider.shared.toggleBookmark(postId: post.id, forceState: newState)

        Task {
            if newState {
                _ = try? await service.bookmarkPost(id: post.id)
            } else {
                _ = try? await service.removeBookmark(id: post.id)
            }
        }
    }

    public func toggleRepost() {
        guard var post = focalPost else { return }
        let newState = !post.isReposted
        post.isReposted = newState
        post.repostCount = max(0, post.repostCount + (newState ? 1 : -1))
        self.focalPost = post
    }
}
