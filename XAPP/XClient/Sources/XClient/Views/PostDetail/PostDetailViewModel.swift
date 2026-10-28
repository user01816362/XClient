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

        do {
            let (postWire, repliesWire) = try await service.fetchPostDetail(postId: postId)

            // Resolve author
            let authorId = postWire.authorId ?? "usr_unknown"
            let author: XUser
            if let concreteService = service as? XClientService, let cached = concreteService.userCache[authorId] {
                author = cached
            } else if let mockService = service as? MockClientService, let cached = mockService.users[authorId] {
                author = cached
            } else {
                author = XUser(id: authorId, name: "User", username: authorId)
            }

            var focal = PostItem(post: postWire, author: author)
            if let mockService = service as? MockClientService {
                focal.isBookmarked = mockService.bookmarkedPostIds.contains(postId)
            }
            self.focalPost = focal

            // Resolve replies
            self.replies = repliesWire.map { replyPost in
                let replyAuthorId = replyPost.authorId ?? "usr_unknown"
                let replyAuthor: XUser
                if let concreteService = service as? XClientService, let cached = concreteService.userCache[replyAuthorId] {
                    replyAuthor = cached
                } else if let mockService = service as? MockClientService, let cached = mockService.users[replyAuthorId] {
                    replyAuthor = cached
                } else {
                    replyAuthor = XUser(id: replyAuthorId, name: "User", username: replyAuthorId)
                }
                var replyItem = PostItem(post: replyPost, author: replyAuthor)
                if let mockService = service as? MockClientService {
                    replyItem.isBookmarked = mockService.bookmarkedPostIds.contains(replyPost.id)
                }
                return replyItem
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    public func submitReply() async {
        guard !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // Creating a top-level post does not create a reply. Preserve the text
        // until the service supports a verified reply mutation.
        errorMessage = "Reply posting is not available yet. Your text has been kept."
    }

    public func toggleLike() {
        guard var post = focalPost else { return }
        let newState = !post.isLiked
        post.isLiked = newState
        post.likeCount = max(0, post.likeCount + (newState ? 1 : -1))
        self.focalPost = post

        if let concreteService = service as? XClientService, let csrf = concreteService.csrfToken {
            Task {
                if newState {
                    _ = try? await concreteService.graphql.likeTweet(
                        tweetId: post.id,
                        authToken: concreteService.token,
                        csrfToken: csrf
                    )
                } else {
                    _ = try? await concreteService.graphql.unlikeTweet(
                        tweetId: post.id,
                        authToken: concreteService.token,
                        csrfToken: csrf
                    )
                }
            }
        }
    }

    public func toggleBookmark() {
        guard var post = focalPost else { return }
        let newState = !post.isBookmarked
        post.isBookmarked = newState
        post.bookmarkCount = max(0, post.bookmarkCount + (newState ? 1 : -1))
        self.focalPost = post

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

        if let concreteService = service as? XClientService, let csrf = concreteService.csrfToken {
            Task {
                _ = try? await concreteService.graphql.retweet(
                    tweetId: post.id,
                    authToken: concreteService.token,
                    csrfToken: csrf
                )
            }
        }
    }
}
