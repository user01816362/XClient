import Testing
import Foundation
import XKit
import XKitModels
import XKitTesting
import XKitAPI
@testable import XClient

/// Dedicated background actor for stress testing cross-actor boundary hops.
private actor StressWorkerActor {
    let service: any XClientServiceProtocol

    init(service: any XClientServiceProtocol) {
        self.service = service
    }

    func queryHomeTimeline() async throws -> [XPost] {
        try await service.fetchHomeTimeline()
    }

    func queryUserProfile(id: String) async throws -> XUser {
        try await service.fetchUserProfile(id: id)
    }

    func queryBookmarks() async throws -> [XPost] {
        let paginated = try await service.fetchBookmarks(paginationToken: nil, maxResults: 20)
        return paginated.data
    }
}

@Suite("Empirical Concurrency & Stress Challenge Tests", .serialized)
struct EmpiricalStressTests {

    // MARK: - Challenge 1: Heavy Concurrency (200 Background Tasks across Actor Boundaries)
    @Test("200 background tasks querying XClientService across actor boundaries under heavy load")
    func testHighConcurrencyActorBoundaryQueries() async throws {
        let service = await MainActor.run {
            XClientService()
        }
        let workerActor = StressWorkerActor(service: service)

        try await withThrowingTaskGroup(of: Int.self) { group in
            for i in 0..<200 {
                group.addTask {
                    if i % 3 == 0 {
                        let posts = try await workerActor.queryHomeTimeline()
                        return posts.count
                    } else if i % 3 == 1 {
                        let user = try await workerActor.queryUserProfile(id: "usr_me_001")
                        return user.username.count
                    } else {
                        let bookmarks = try await workerActor.queryBookmarks()
                        return bookmarks.count
                    }
                }
            }

            var completedTasks = 0
            for try await result in group {
                #expect(result > 0)
                completedTasks += 1
            }
            #expect(completedTasks == 200)
        }
    }

    // MARK: - Challenge 2: Direct MockDataProvider Wire Interceptor Concurrency (200 Tasks)
    @Test("200 concurrent tasks making wire requests through makeMockClient HTTP interceptor")
    func testWireInterceptorHeavyConcurrency() async throws {
        let client = await MainActor.run {
            MockDataProvider.makeMockClient()
        }

        try await withThrowingTaskGroup(of: String.self) { group in
            for i in 0..<200 {
                group.addTask {
                    if i % 4 == 0 {
                        let me = try await client.users.me(token: "test_token")
                        return me.id
                    } else if i % 4 == 1 {
                        let timeline = try await client.timelines.reverseChronologicalHome(userId: "usr_me_001", token: "test_token")
                        return timeline.data.first?.id ?? ""
                    } else if i % 4 == 2 {
                        let user = try await client.users.lookup(id: "usr_author_002", token: "test_token")
                        return user.id
                    } else {
                        let bookmarks = try await client.bookmarks.list(userId: "usr_me_001", token: "test_token")
                        return bookmarks.data.first?.id ?? ""
                    }
                }
            }

            var count = 0
            for try await id in group {
                #expect(!id.isEmpty)
                count += 1
            }
            #expect(count == 200)
        }
    }

    // MARK: - Challenge 3: Rapid Mutation Under Read Contention
    @Test("Concurrent readers and writers under active mutation contention")
    func testRapidMutationUnderReadContention() async throws {
        await MainActor.run {
            MockDataProvider.shared.resetToDefaults()
        }
        let service = await MainActor.run {
            XClientService()
        }

        let writeCount = 30
        let readCount = 70

        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<writeCount {
                group.addTask {
                    if i % 3 == 0 {
                        _ = try await service.createPost(text: "Contention post \(i)")
                    } else if i % 3 == 1 {
                        _ = try await service.bookmarkPost(id: "post_1002")
                    } else {
                        _ = try await service.removeBookmark(id: "post_1002")
                    }
                }
            }

            for i in 0..<readCount {
                group.addTask {
                    if i % 2 == 0 {
                        let posts = try await service.fetchHomeTimeline()
                        #expect(!posts.isEmpty)
                    } else {
                        let bookmarks = try await service.fetchBookmarks(paginationToken: nil, maxResults: 10)
                        #expect(bookmarks.data.count >= 0)
                    }
                }
            }

            try await group.waitForAll()
        }

        let finalTimeline = try await service.fetchHomeTimeline()
        #expect(finalTimeline.count >= 10)
    }

    // MARK: - Challenge 4: Post ID Collisions Under Rapid Creation (MockDataProvider)
    @Test("Verify uniqueness of post IDs generated under rapid creation in MockDataProvider")
    func testMockDataProviderPostIdUniqueness() async throws {
        await MainActor.run {
            MockDataProvider.shared.resetToDefaults()
        }
        let service = await MainActor.run {
            XClientService()
        }

        var createdIds: [String] = []
        for i in 0..<20 {
            let post = try await service.createPost(text: "Rapid sequential post \(i)")
            createdIds.append(post.id)
        }

        let uniqueIds = Set(createdIds)
        #expect(uniqueIds.count == createdIds.count, "Generated post IDs must be unique! Found \(uniqueIds.count) unique IDs out of \(createdIds.count) created posts.")
    }

    // MARK: - Challenge 5: Post ID Collisions in MockClientService
    @Test("Verify uniqueness of post IDs generated under rapid creation in MockClientService")
    func testMockClientServicePostIdUniqueness() async throws {
        let mockService = await MainActor.run {
            MockClientService()
        }

        var createdIds: [String] = []
        for i in 0..<20 {
            let post = try await mockService.createPost(text: "MockClientService rapid post \(i)")
            createdIds.append(post.id)
        }

        let uniqueIds = Set(createdIds)
        #expect(uniqueIds.count == createdIds.count, "MockClientService generated post IDs must be unique! Found \(uniqueIds.count) unique IDs out of \(createdIds.count) created posts.")
    }

    // MARK: - Challenge 6: Impact of Colliding IDs on Deletion Cascade
    @Test("Deletion cascade bug caused by non-unique post IDs")
    func testDeletionCascadeWithCollidingIds() async throws {
        await MainActor.run {
            MockDataProvider.shared.resetToDefaults()
        }
        let service = await MainActor.run {
            XClientService()
        }

        let p1 = try await service.createPost(text: "Post Alpha")
        let p2 = try await service.createPost(text: "Post Beta")

        if p1.id == p2.id {
            let countBefore = await MainActor.run { MockDataProvider.shared.timelinePosts.count }
            _ = try await service.deletePost(id: p1.id)
            let countAfter = await MainActor.run { MockDataProvider.shared.timelinePosts.count }

            #expect(countBefore - countAfter == 1, "Deleting one post should decrease total count by exactly 1, but decreased by \(countBefore - countAfter) because both had ID \(p1.id)")
        }
    }

    // MARK: - Challenge 7: Bookmark Count Drift on Non-State-Changing Calls
    @Test("Bookmark counter drift on repeated forceState operations")
    func testBookmarkCounterDrift() async throws {
        await MainActor.run {
            MockDataProvider.shared.resetToDefaults()
        }
        let service = await MainActor.run {
            XClientService()
        }

        // post_1002 starts unbookmarked with 310 bookmarks
        let initialCount = await MainActor.run {
            MockDataProvider.shared.postItems.first(where: { $0.id == "post_1002" })!.bookmarkCount
        }

        // Removing an unbookmarked post should be a no-op on the counter
        _ = try await service.removeBookmark(id: "post_1002")

        let countAfter = await MainActor.run {
            MockDataProvider.shared.postItems.first(where: { $0.id == "post_1002" })!.bookmarkCount
        }

        #expect(countAfter == initialCount, "Removing an unbookmarked post must not decrement bookmark count! Initial: \(initialCount), After: \(countAfter)")
    }

    // MARK: - Challenge 8: User Tweets Endpoint Isolation by UserId
    @Test("User tweets endpoint must filter by requested userId")
    func testUserTweetsEndpointIsolation() async throws {
        let service = await MainActor.run {
            XClientService()
        }

        // Request tweets for usr_author_002 (Swift Core Team)
        let response = try await service.fetchUserPosts(userId: "usr_author_002", paginationToken: nil, maxResults: 10)

        // All returned tweets should belong to author usr_author_002
        for post in response.data {
            #expect(post.authorId == "usr_author_002", "Expected author usr_author_002 but got \(post.authorId)")
        }
    }

    // MARK: - Challenge 9: User Likes Query Isolation
    @Test("likesForUser query helper must filter by user ID")
    @MainActor
    func testLikesForUserFilter() async throws {
        let provider = MockDataProvider.shared
        provider.resetToDefaults()

        // usr_author_005 (Alex) has zero liked posts in default fixtures
        let alexLikes = provider.likesForUser(id: "usr_author_005")

        // If likesForUser ignores the id parameter, it returns all globally liked posts (p1, p7, etc.)
        #expect(alexLikes.allSatisfy { $0.author.id == "usr_author_005" }, "likesForUser must only return posts liked by the requested user")
    }

    // MARK: - Challenge 10: Heavy Throughput Load (410 Calls)
    @Test("410 sequential and concurrent requests sustained throughput")
    func testHeavyThroughputLoad() async throws {
        let service = await MainActor.run {
            XClientService()
        }

        let startTime = Date()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    _ = try await service.fetchHomeTimeline(paginationToken: nil, maxResults: 5)
                    _ = try await service.fetchUserProfile(id: "usr_me_001")
                    _ = try await service.fetchBookmarks(paginationToken: nil, maxResults: 5)
                    _ = try await service.fetchUserPosts(userId: "usr_me_001", paginationToken: nil, maxResults: 5)
                    if i % 10 == 0 {
                        _ = try await service.fetchCurrentUser()
                    }
                }
            }
            try await group.waitForAll()
        }
        let elapsed = Date().timeIntervalSince(startTime)
        #expect(elapsed < 10.0, "Heavy load of 410 calls should complete within 10 seconds, took \(elapsed)s")
    }
}
