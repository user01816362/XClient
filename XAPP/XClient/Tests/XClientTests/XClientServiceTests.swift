import Testing
import Foundation
import XKit
import XKitModels
import XKitTransport
import XKitTesting
import XKitAPI
@testable import XClient

@Suite("XClientService Tests", .serialized)
struct XClientServiceTests {

    @Test("Service initializes with default mock provider and credentials")
    @MainActor
    func testInitialization() async throws {
        let service = XClientService()
        #expect(service.token == "mock_token")
        #expect(service.currentUserId == MockDataProvider.shared.currentUser.id)
        #expect(!service.currentUserId.isEmpty)
    }

    @Test("Updating credentials updates active token and currentUserId")
    @MainActor
    func testUpdateCredentials() async throws {
        let service = XClientService()
        service.updateCredentials(token: "custom_bearer_123", currentUserId: "user_456")
        #expect(service.token == "custom_bearer_123")
        #expect(service.currentUserId == "user_456")
    }

    @Test("fetchHomeTimeline returns deterministic posts from mock provider")
    @MainActor
    func testFetchHomeTimeline() async throws {
        let service = XClientService()
        let posts = try await service.fetchHomeTimeline()

        #expect(!posts.isEmpty)
        #expect(posts.count == MockDataProvider.shared.timelinePosts.count)
        #expect(posts.first?.id == MockDataProvider.shared.timelinePosts.first?.id)
    }

    @Test("fetchHomeTimeline with pagination passes query items and returns paginated response")
    @MainActor
    func testFetchHomeTimelinePagination() async throws {
        let service = XClientService()
        let response = try await service.fetchHomeTimeline(paginationToken: "next_cursor_1", maxResults: 5)

        #expect(response.data.count <= 5)
        #expect(response.resultCount != nil)
    }

    @Test("fetchUserProfile fetches user by ID accurately")
    @MainActor
    func testFetchUserProfile() async throws {
        let service = XClientService()
        let targetUserId = "990002" // Sarah Jenkins
        let user = try await service.fetchUserProfile(id: targetUserId)

        #expect(user.id == targetUserId)
        #expect(user.username == "sarah_design")
        #expect(user.verified == true)
    }

    @Test("fetchUserProfile with invalid ID throws API error")
    @MainActor
    func testFetchUserProfileNotFound() async throws {
        let service = XClientService()
        await #expect(throws: XKitError.self) {
            _ = try await service.fetchUserProfile(id: "nonexistent_999999")
        }
    }

    @Test("createPost appends post and returns generated XPost")
    @MainActor
    func testCreatePost() async throws {
        let service = XClientService()
        let newText = "Testing automated post creation from XClientService unit test."
        let post = try await service.createPost(text: newText)

        #expect(post.text == newText)
        #expect(post.authorId == service.currentUserId)
        #expect(!post.id.isEmpty)
    }

    @Test("deletePost removes post and returns true")
    @MainActor
    func testDeletePost() async throws {
        let service = XClientService()
        let created = try await service.createPost(text: "Temporary post to delete")
        let deleted = try await service.deletePost(id: created.id)
        #expect(deleted == true)
    }

    @Test("bookmarkPost and removeBookmark mutate bookmark state")
    @MainActor
    func testBookmarkWorkflow() async throws {
        let service = XClientService()
        let postId = "post_1001"

        let added = try await service.bookmarkPost(id: postId)
        #expect(added == true)

        let removed = try await service.removeBookmark(id: postId)
        #expect(removed == true)
    }

    @Test("HTTP 429 rate limit correctly propagates XKitError.rateLimitExceeded")
    @MainActor
    func testRateLimitPropagation() async throws {
        let mockTransport = MockTransport()
        let resetEpoch = "\(Int(Date().timeIntervalSince1970 + 120))"
        mockTransport.enqueue(statusCode: 429, headers: ["x-rate-limit-reset": resetEpoch], data: Data())

        let client = XKit.XClient(transport: mockTransport)
        let service = XClientService(client: client)

        await #expect(throws: XKitError.self) {
            _ = try await service.fetchHomeTimeline()
        }
    }
}
