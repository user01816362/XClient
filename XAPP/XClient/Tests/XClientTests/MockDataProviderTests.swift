import Foundation
import Testing
@testable import XClient
import XKitModels
import XKitAPI

@Suite("Mock Data Provider Concurrency & Wire Fidelity Tests", .serialized)
struct MockDataProviderTests {

    @Test("Verify Initial State and Deterministic Fixtures")
    @MainActor
    func testInitialState() async throws {
        // Use an isolated instance to eliminate cross-suite race conditions
        let provider = MockDataProvider()

        #expect(provider.currentUser.username == "liquidglass")
        #expect(provider.currentUser.verified == true)
        #expect(provider.timelinePosts.count == 10)
        #expect(provider.bookmarks.count == 4)
        #expect(provider.postItems.count == 10)
    }

    @Test("Verify UsersService.me via makeMockClient")
    @MainActor
    func testUsersServiceMe() async throws {
        let provider = MockDataProvider()
        let client = provider.makeMockClient()
        let user = try await client.users.me(token: "mock_test_token")

        #expect(user.id == "usr_me_001")
        #expect(user.username == "liquidglass")
        #expect(user.name == "Liquid Glass")
    }

    @Test("Verify TimelinesService.reverseChronologicalHome via makeMockClient")
    @MainActor
    func testTimelineFetch() async throws {
        let provider = MockDataProvider()
        let client = provider.makeMockClient()
        let response = try await client.timelines.reverseChronologicalHome(
            userId: "usr_me_001",
            token: "mock_test_token"
        )

        #expect(response.data.count == 10)
        #expect(response.data.first?.id == "post_1001")
    }

    @Test("Verify Post Creation and Dynamic Timeline Update")
    @MainActor
    func testPostCreation() async throws {
        let provider = MockDataProvider()
        let client = provider.makeMockClient()

        let initialCount = provider.timelinePosts.count
        let newPost = try await client.posts.create(
            text: "Testing dynamic post creation in offline mock!",
            token: "mock_test_token"
        )

        #expect(newPost.text == "Testing dynamic post creation in offline mock!")
        #expect(provider.timelinePosts.count == initialCount + 1)
        #expect(provider.timelinePosts.first?.id == newPost.id)
    }

    @Test("Verify Bookmark Toggle Operations")
    @MainActor
    func testBookmarkOperations() async throws {
        let provider = MockDataProvider()
        let client = provider.makeMockClient()

        // Bookmark post_1002 (currently not bookmarked)
        let added = try await client.bookmarks.add(
            userId: "usr_me_001",
            postId: "post_1002",
            token: "mock_test_token"
        )
        #expect(added == true)
        #expect(provider.bookmarks.contains(where: { $0.id == "post_1002" }))

        // Remove bookmark post_1002
        let removed = try await client.bookmarks.remove(
            userId: "usr_me_001",
            postId: "post_1002",
            token: "mock_test_token"
        )
        #expect(removed == true)
        #expect(!provider.bookmarks.contains(where: { $0.id == "post_1002" }))
    }

    @Test("Verify Post Deletion")
    @MainActor
    func testPostDeletion() async throws {
        let provider = MockDataProvider()
        let client = provider.makeMockClient()

        let deleted = try await client.posts.delete(id: "post_1001", token: "mock_test_token")
        #expect(deleted == true)
        #expect(!provider.timelinePosts.contains(where: { $0.id == "post_1001" }))
    }

    @Test("Verify 404 Problem Details on Unknown User Lookup")
    @MainActor
    func testUserNotFound() async throws {
        let provider = MockDataProvider()
        let client = provider.makeMockClient()

        await #expect(throws: XKitError.self) {
            _ = try await client.users.lookup(username: "nonexistent_ghost_user_999", token: "mock_test_token")
        }
    }

    @Test("Verify Strict Concurrency and Cross-Actor Safety")
    func testCrossActorSafety() async throws {
        let provider = await MainActor.run { MockDataProvider() }
        // Accessing MockDataProvider from a detached background task with await
        let postCount = await Task.detached {
            await provider.timelinePosts.count
        }.value

        #expect(postCount >= 10)
    }
}
