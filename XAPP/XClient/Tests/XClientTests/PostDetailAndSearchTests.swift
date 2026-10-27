//
//  PostDetailAndSearchTests.swift
//  XClientTests
//
//  Unit tests covering PostDetailViewModel conversation loading,
//  social action toggling, inline reply submission, and SearchViewModel execution.
//  100% Swift 6 strict concurrency compliance.
//

import Testing
import Foundation
@testable import XClient
import XKitModels

@Suite("Post Detail, Thread Conversation & Search Tests")
@MainActor
struct PostDetailAndSearchTests {

    @Test("PostDetailViewModel loads focal post and replies from service")
    func testPostDetailLoading() async {
        let mock = MockDataProvider.shared
        mock.resetToDefaults()

        let targetPost = mock.postItems.first!
        let vm = PostDetailViewModel(postId: targetPost.id)

        await vm.loadPostDetail()

        #expect(vm.focalPost != nil)
        #expect(vm.focalPost?.id == targetPost.id)
        #expect(vm.focalPost?.text == targetPost.text)
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
    }

    @Test("PostDetailViewModel toggles like and updates like count")
    func testPostDetailLikeToggle() async {
        let localService = MockClientService()
        let targetPost = localService.timelinePosts.first!
        let vm = PostDetailViewModel(postId: targetPost.id, service: localService)
        await vm.loadPostDetail()

        let initialLiked = vm.focalPost?.isLiked ?? false
        let initialCount = vm.focalPost?.likeCount ?? 0

        vm.toggleLike()

        let expectedCount = max(0, initialCount + (initialLiked ? -1 : 1))
        #expect(vm.focalPost?.isLiked == !initialLiked)
        #expect(vm.focalPost?.likeCount == expectedCount)
    }

    @Test("PostDetailViewModel toggles bookmark and updates bookmark count")
    func testPostDetailBookmarkToggle() async {
        let localService = MockClientService()
        let targetPost = localService.timelinePosts.first!
        let vm = PostDetailViewModel(postId: targetPost.id, service: localService)
        await vm.loadPostDetail()

        let initialBookmarked = vm.focalPost?.isBookmarked ?? false
        let initialCount = vm.focalPost?.bookmarkCount ?? 0

        vm.toggleBookmark()

        let expectedCount = max(0, initialCount + (initialBookmarked ? -1 : 1))
        #expect(vm.focalPost?.isBookmarked == !initialBookmarked)
        #expect(vm.focalPost?.bookmarkCount == expectedCount)
    }

    @Test("PostDetailViewModel submits inline reply and increments reply count")
    func testPostDetailSubmitReply() async {
        let localService = MockClientService()
        let targetPost = localService.timelinePosts.first!
        let vm = PostDetailViewModel(postId: targetPost.id, service: localService)
        await vm.loadPostDetail()

        let initialReplyCount = vm.focalPost?.replyCount ?? 0
        let initialRepliesCount = vm.replies.count

        vm.replyText = "Fascinating perspective on Liquid Glass design!"
        await vm.submitReply()

        #expect(vm.replies.count == initialRepliesCount + 1)
        #expect(vm.replies.first?.text == "Fascinating perspective on Liquid Glass design!")
        #expect(vm.focalPost?.replyCount == initialReplyCount + 1)
        #expect(vm.replyText.isEmpty)
        #expect(vm.isSubmittingReply == false)
    }

    @Test("SearchViewModel executes query and filters matching posts")
    func testSearchViewModelExecution() async {
        let localService = MockClientService()
        let vm = SearchViewModel(service: localService)
        #expect(vm.searchResults.isEmpty)

        // Query for "Liquid Glass"
        await vm.executeSearch(query: "Liquid Glass")

        #expect(!vm.searchResults.isEmpty)
        for result in vm.searchResults {
            #expect(result.text.localizedCaseInsensitiveContains("Liquid Glass"))
        }
        #expect(vm.isSearching == false)
    }

    @Test("MediaLightboxViewModel initializes with default scale 1.0 and zero offset")
    func testMediaLightboxViewModelInit() {
        let model = MediaLightboxViewModel()
        #expect(model.currentScale == 1.0)
        #expect(model.lastScale == 1.0)
        #expect(model.offset == .zero)
        #expect(model.isSavedToPhotos == false)
        #expect(model.isSaving == false)
    }
}
