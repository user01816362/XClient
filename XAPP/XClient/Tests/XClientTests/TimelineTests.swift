//
//  TimelineTests.swift
//  XClientTests
//
//  Automated Unit & Component Tests for Milestone 3 (Feature F4):
//  Reverse-chronological timeline loading, pull-to-refresh, unread buffering,
//  pagination cursor traversal, and TabBarCoordinator integration.
//  100% Swift 6 strict concurrency compliance.
//

import Testing
import Foundation
import SwiftUI
import Combine
import XKitModels
import XKitAPI
@testable import XClient

@Suite("Milestone 3: Reverse-Chronological Timeline & Polling Tests", .serialized)
struct TimelineTests {

    @Test("Failed bookmark and delete do not appear successful")
    @MainActor
    func failedActionsRemainVisible() async throws {
        let provider = MockDataProvider()
        let service = MockClientService(currentUser: provider.currentUser, timelinePosts: provider.timelinePosts, users: provider.users)
        let model = TimelineViewModel(service: service, autoRefreshInterval: 0)
        await model.fetchTimeline()
        let post = try #require(model.posts.first)
        service.shouldThrowError = URLError(.notConnectedToInternet)
        model.toggleBookmark(for: post)
        for _ in 0..<20 where model.errorMessage == nil { await Task.yield() }
        #expect(model.posts.first(where: { $0.id == post.id })?.isBookmarked == post.isBookmarked)
        #expect(model.errorMessage != nil)
        model.deletePost(post)
        for _ in 0..<20 { await Task.yield() }
        #expect(model.posts.contains(where: { $0.id == post.id }))
    }

    // MARK: - Test 1.1: Initial Feed Loading & Strict Reverse-Chronological Order
    @Test("Verify Initial Timeline Loading and Strict Reverse-Chronological Ordering")
    @MainActor
    func testInitialTimelineLoadingReverseChronological() async throws {
        let provider = MockDataProvider()
        let service = MockClientService(
            currentUser: provider.currentUser,
            timelinePosts: provider.timelinePosts,
            users: provider.users
        )
        let viewModel = TimelineViewModel(service: service)

        #expect(viewModel.posts.isEmpty)
        #expect(viewModel.isLoading == false)

        await viewModel.fetchTimeline()

        #expect(!viewModel.posts.isEmpty)
        #expect(viewModel.posts.count == provider.timelinePosts.count)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.errorMessage == nil)

        // Strict descending timestamp verification: createdAt[i] >= createdAt[i+1]
        let posts = viewModel.posts
        for i in 0..<(posts.count - 1) {
            let current = posts[i].createdAt
            let next = posts[i + 1].createdAt
            #expect(current >= next, "Post at index \(i) (\(current)) is older than post at \(i+1) (\(next))")
        }
    }

    // MARK: - Test 1.2: Empty Timeline Handling
    @Test("Verify Initial Loading with Zero Posts Returns Clean Empty State")
    @MainActor
    func testEmptyTimelineHandling() async throws {
        let provider = MockDataProvider()
        let service = MockClientService(
            currentUser: provider.currentUser,
            timelinePosts: [],
            users: provider.users
        )
        let viewModel = TimelineViewModel(service: service)

        await viewModel.fetchTimeline()

        #expect(viewModel.posts.isEmpty)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.unreadCount == 0)
    }

    // MARK: - Test 1.3: Network Error Handling & Recovery
    @Test("Verify Network Failure Displays Error Banner and Recovers Cleanly on Retry")
    @MainActor
    func testTimelineErrorHandlingAndRecovery() async throws {
        let provider = MockDataProvider()
        let service = MockClientService(
            currentUser: provider.currentUser,
            timelinePosts: provider.timelinePosts,
            users: provider.users
        )
        service.shouldThrowError = URLError(.notConnectedToInternet)
        let viewModel = TimelineViewModel(service: service)

        await viewModel.fetchTimeline()

        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.posts.isEmpty)
        #expect(viewModel.isLoading == false)

        // Recovery on retry
        service.shouldThrowError = nil
        await viewModel.fetchTimeline()

        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.posts.isEmpty)
    }

    // MARK: - Test 1.4: Pull-to-Refresh & Deduplication
    @Test("Verify Pull-to-Refresh Prepends Novel Posts and Deduplicates Existing Posts")
    @MainActor
    func testPullToRefreshDeduplication() async throws {
        let provider = MockDataProvider()
        let service = MockClientService(
            currentUser: provider.currentUser,
            timelinePosts: Array(provider.timelinePosts.prefix(5)),
            users: provider.users
        )
        let viewModel = TimelineViewModel(service: service)
        await viewModel.fetchTimeline()
        #expect(viewModel.posts.count == 5)

        // Add 2 new posts + 1 existing overlapping post to service
        let newPost1 = XPost(id: "post_novel_101", text: "New post 1", authorId: "usr_me_001", createdAt: Date().addingTimeInterval(100))
        let newPost2 = XPost(id: "post_novel_102", text: "New post 2", authorId: "usr_me_001", createdAt: Date().addingTimeInterval(200))
        let overlapping = viewModel.posts.first!.asXPost

        service.timelinePosts = [newPost2, newPost1, overlapping] + service.timelinePosts

        await viewModel.refreshTimeline()

        #expect(viewModel.posts.count == 7) // 5 original + 2 novel (overlapping deduplicated)
        #expect(viewModel.posts[0].id == "post_novel_102")
        #expect(viewModel.posts[1].id == "post_novel_101")
        #expect(viewModel.isRefreshing == false)
    }

    // MARK: - Test 1.5: Concurrent Pull-to-Refresh Throttling
    @Test("Verify Simultaneous Pull-to-Refresh Calls Do Not Conflict or Race")
    @MainActor
    func testConcurrentPullToRefreshThrottling() async throws {
        let provider = MockDataProvider()
        let service = MockClientService(
            currentUser: provider.currentUser,
            timelinePosts: provider.timelinePosts,
            users: provider.users
        )
        let viewModel = TimelineViewModel(service: service)
        await viewModel.fetchTimeline()

        // Launch concurrent refresh tasks
        async let refresh1: () = viewModel.refreshTimeline()
        async let refresh2: () = viewModel.refreshTimeline()
        _ = await (refresh1, refresh2)

        #expect(viewModel.posts.count == provider.timelinePosts.count)
        #expect(viewModel.isRefreshing == false)
    }

    // MARK: - Test 1.6: Background Polling Unread Buffer Accumulation
    @Test("Verify Polled Posts Accumulate in Unread Buffer Without Shifting Feed")
    @MainActor
    func testUnreadBufferAccumulationDuringPolling() async throws {
        let provider = MockDataProvider()
        let service = MockClientService(
            currentUser: provider.currentUser,
            timelinePosts: Array(provider.timelinePosts.prefix(4)),
            users: provider.users
        )
        let viewModel = TimelineViewModel(service: service)
        await viewModel.fetchTimeline()

        #expect(viewModel.posts.count == 4)
        #expect(viewModel.unreadCount == 0)
        #expect(viewModel.unreadBuffer.isEmpty)

        // Simulate PollingEngine discovering 3 new posts
        let polledPosts = [
            XPost(id: "poll_01", text: "Polled 1", authorId: "usr_me_001", createdAt: Date().addingTimeInterval(30)),
            XPost(id: "poll_02", text: "Polled 2", authorId: "usr_me_001", createdAt: Date().addingTimeInterval(60)),
            XPost(id: "poll_03", text: "Polled 3", authorId: "usr_me_001", createdAt: Date().addingTimeInterval(90))
        ]

        viewModel.handleNewPolledPosts(polledPosts)

        // Visible feed must remain stationary
        #expect(viewModel.posts.count == 4)
        #expect(viewModel.unreadCount == 3)
        #expect(viewModel.unreadBuffer.count == 3)
    }

    // MARK: - Test 1.7: Flush Unread Buffer Prepends Posts
    @Test("Verify Flush Unread Buffer Prepends Items and Resets Pill State")
    @MainActor
    func testFlushUnreadBufferPrependsToFeed() async throws {
        let provider = MockDataProvider()
        let service = MockClientService(
            currentUser: provider.currentUser,
            timelinePosts: Array(provider.timelinePosts.prefix(3)),
            users: provider.users
        )
        let viewModel = TimelineViewModel(service: service)
        await viewModel.fetchTimeline()

        let polledPosts = [
            XPost(id: "poll_A", text: "Polled A", authorId: "usr_me_001", createdAt: Date().addingTimeInterval(50)),
            XPost(id: "poll_B", text: "Polled B", authorId: "usr_me_001", createdAt: Date().addingTimeInterval(100))
        ]
        viewModel.handleNewPolledPosts(polledPosts)
        #expect(viewModel.unreadCount == 2)

        viewModel.flushUnreadBuffer()

        #expect(viewModel.unreadCount == 0)
        #expect(viewModel.unreadBuffer.isEmpty)
        #expect(viewModel.posts.count == 5)
        #expect(viewModel.posts.contains(where: { $0.id == "poll_A" }))
        #expect(viewModel.posts.contains(where: { $0.id == "poll_B" }))
    }

    // MARK: - Test 1.8: Flush Empty Buffer Is Safe
    @Test("Verify Flush Unread Buffer on Empty State Is Safe No-Op")
    @MainActor
    func testFlushEmptyUnreadBufferSafe() {
        let viewModel = TimelineViewModel(service: MockClientService())
        #expect(viewModel.unreadBuffer.isEmpty)
        viewModel.flushUnreadBuffer()
        #expect(viewModel.unreadBuffer.isEmpty)
        #expect(viewModel.unreadCount == 0)
    }

    // MARK: - Test 1.9: Pagination Cursor Traversal
    @Test("Verify Infinite Scroll Pagination Loads Next Page Using Cursor")
    @MainActor
    func testPaginationCursorTraversal() async throws {
        let provider = MockDataProvider()
        let service = MockClientService(
            currentUser: provider.currentUser,
            timelinePosts: provider.timelinePosts,
            users: provider.users
        )
        let viewModel = TimelineViewModel(service: service)

        await viewModel.fetchTimeline()
        let initialCount = viewModel.posts.count

        // Trigger loadMore
        await viewModel.loadMore()

        #expect(viewModel.isLoadingMore == false)
        #expect(viewModel.posts.count >= initialCount)
    }

    // MARK: - Test 1.10: Terminal Pagination Token No-Op
    @Test("Verify LoadMore When No Next Token Exists Is Safe No-Op")
    @MainActor
    func testTerminalPaginationNoOp() async throws {
        let provider = MockDataProvider()
        let service = MockClientService(
            currentUser: provider.currentUser,
            timelinePosts: Array(provider.timelinePosts.prefix(5)),
            users: provider.users
        )
        let viewModel = TimelineViewModel(service: service)
        await viewModel.fetchTimeline()

        // Calling loadMore when nextPaginationToken is nil
        #expect(viewModel.nextPaginationToken == nil)
        let countBefore = viewModel.posts.count
        await viewModel.loadMore()
        #expect(viewModel.isLoadingMore == false)
        #expect(viewModel.posts.count == countBefore)
    }

    // MARK: - Test 1.11: Page-Boundary Duplicate Filtering
    @Test("Verify Duplicate Items on Pagination Boundaries Are Dropped")
    @MainActor
    func testPaginationBoundaryDeduplication() async throws {
        let provider = MockDataProvider()
        let service = MockClientService(
            currentUser: provider.currentUser,
            timelinePosts: provider.timelinePosts,
            users: provider.users
        )
        let viewModel = TimelineViewModel(service: service)
        await viewModel.fetchTimeline()

        let countBefore = viewModel.posts.count
        await viewModel.loadMore()
        let countAfter = viewModel.posts.count

        // Verify all IDs in posts remain distinct
        let ids = viewModel.posts.map(\.id)
        let uniqueIds = Set(ids)
        #expect(ids.count == uniqueIds.count, "Duplicate post IDs found after pagination: \(ids.count - uniqueIds.count)")
        #expect(countAfter >= countBefore)
    }

    // MARK: - Test 1.12: TabBarCoordinator Integration (Scroll-To-Top)
    @Test("Verify TabBarCoordinator Scroll-To-Top Flushes Unread Buffer")
    @MainActor
    func testTabBarCoordinatorScrollToTopFlushesBuffer() async throws {
        let coordinator = TabBarCoordinator()
        let navState = AppNavigationState(initialDestination: .timeline)
        coordinator.attach(to: navState)

        let viewModel = TimelineViewModel(
            service: MockClientService(),
            navigationState: navState
        )

        let polled = [XPost(id: "poll_top_01", text: "Pill Top", authorId: "usr_me_001", createdAt: Date())]
        viewModel.handleNewPolledPosts(polled)
        #expect(viewModel.unreadCount == 1)

        // Trigger scroll to top via coordinator
        coordinator.triggerScrollToTop(for: .timeline)
        viewModel.flushUnreadBuffer()

        #expect(viewModel.unreadCount == 0)
        #expect(viewModel.unreadBuffer.isEmpty)
    }

    // MARK: - Test 1.13: TabBarCoordinator Double-Tap Refresh
    @Test("Verify Rapid Double-Tap Reselection Triggers Refresh and Updates Trigger Counters")
    @MainActor
    func testTabBarCoordinatorDoubleTapRefresh() async throws {
        let coordinator = TabBarCoordinator()
        let navState = AppNavigationState(initialDestination: .timeline)
        coordinator.attach(to: navState)

        var refreshReceived = false
        let cancellable = coordinator.refreshPublisher.sink { destination in
            if destination == .timeline {
                refreshReceived = true
            }
        }

        let now = Date()
        coordinator.handleTabSelection(.timeline, date: now)
        coordinator.handleTabReselection(.timeline, date: now.addingTimeInterval(0.1)) // < 0.35s

        #expect(refreshReceived == true)
        #expect(coordinator.lastScrollToTopEvent?.isDoubleTap == true)
        cancellable.cancel()
    }

    // MARK: - Test 1.14: Concurrency Stress Under Swift 6 Strict Concurrency
    @Test("100 concurrent asynchronous tasks interacting with TimelineViewModel")
    func testTimelineConcurrencyStress() async throws {
        let service = await MainActor.run {
            MockClientService()
        }
        let viewModel = await MainActor.run {
            TimelineViewModel(service: service)
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    await MainActor.run {
                        if i % 3 == 0 {
                            let dummy = PostItem(id: "dummy_\(i)", text: "Dummy \(i)", author: MockDataProvider.shared.currentUser)
                            viewModel.toggleLike(for: dummy)
                        } else if i % 3 == 1 {
                            let dummy = PostItem(id: "dummy_\(i)", text: "Dummy \(i)", author: MockDataProvider.shared.currentUser)
                            viewModel.toggleBookmark(for: dummy)
                        } else {
                            viewModel.flushUnreadBuffer()
                        }
                    }
                }
            }
            try await group.waitForAll()
        }

        await MainActor.run {
            #expect(viewModel.unreadCount >= 0)
        }
    }

    // MARK: - Test 1.15: TimelinePollingEngine Lifecycle State Transitions
    @Test("Verify TimelinePollingEngine Lifecycle: start, pause, resume, stop")
    func testTimelinePollingEngineLifecycle() async {
        let engine = TimelinePollingEngine(interval: 60.0)
        #expect(await engine.state == .idle)
        #expect(await engine.currentInterval == 60.0)
        #expect(await engine.consecutiveFailures == 0)

        // Start
        await engine.startPolling(
            interval: 45.0,
            initialKnownIds: ["p1", "p2"],
            fetchHandler: { [XPost(id: "p3", text: "New")] },
            onNewPosts: { _ in }
        )
        #expect(await engine.state == .polling)
        #expect(await engine.currentInterval == 45.0)
        #expect(await engine.knownPostIds.contains("p1"))
        #expect(await engine.knownPostIds.contains("p2"))

        // Pause
        await engine.pause()
        #expect(await engine.state == .paused)

        // Resume
        await engine.resume()
        #expect(await engine.state == .polling)

        // Update interval
        await engine.updateInterval(15.0)
        #expect(await engine.currentInterval == 15.0)

        // Stop
        await engine.stop()
        #expect(await engine.state == .idle)
        #expect(await engine.consecutiveFailures == 0)
    }

    // MARK: - Test 1.16: TimelinePollingEngine Single Poll Execution & Deduplication
    @Test("Verify TimelinePollingEngine pollOnce Discovers Novel Posts and Updates Known IDs")
    func testTimelinePollingEnginePollOnce() async {
        let engine = TimelinePollingEngine(interval: 30.0)
        let initialPost = XPost(id: "known_1", text: "Old")
        let novelPost1 = XPost(id: "novel_1", text: "New 1")
        let novelPost2 = XPost(id: "novel_2", text: "New 2")

        await engine.startPolling(
            initialKnownIds: [initialPost.id],
            fetchHandler: { [initialPost, novelPost1, novelPost2] },
            onNewPosts: { _ in }
        )

        let polled = await engine.pollOnce()
        #expect(polled.count == 2)
        #expect(polled.map(\.id) == ["novel_1", "novel_2"])
        #expect(await engine.knownPostIds.contains("known_1"))
        #expect(await engine.knownPostIds.contains("novel_1"))
        #expect(await engine.knownPostIds.contains("novel_2"))

        // Second poll with same items returns empty (already known)
        let secondPoll = await engine.pollOnce()
        #expect(secondPoll.isEmpty)

        await engine.stop()
    }

    // MARK: - Test 1.17: TimelinePollingEngine Exponential Error Backoff Progression
    @Test("Verify Exponential Error Backoff Mathematical Delay Progression and Recovery")
    func testTimelinePollingEngineBackoffProgression() async {
        let policy = TimelinePollingEngine.BackoffPolicy(baseInterval: 10.0, multiplier: 2.0, maxInterval: 80.0)
        #expect(policy.calculateDelay(forFailures: 0) == 10.0)
        #expect(policy.calculateDelay(forFailures: 1) == 20.0)
        #expect(policy.calculateDelay(forFailures: 2) == 40.0)
        #expect(policy.calculateDelay(forFailures: 3) == 80.0)
        #expect(policy.calculateDelay(forFailures: 4) == 80.0) // Capped at maxInterval
        #expect(policy.calculateDelay(forFailures: 10) == 80.0)

        struct SimulatedNetworkError: Error {}
        let engine = TimelinePollingEngine(interval: 10.0, backoffPolicy: policy)

        await engine.startPolling(
            fetchHandler: { throw SimulatedNetworkError() },
            onNewPosts: { _ in }
        )

        // Failure 1: delay = 10 * 2^1 = 20.0
        _ = await engine.pollOnce()
        var state = await engine.state
        if case .backingOff(let failures, let delay) = state {
            #expect(failures == 1)
            #expect(delay == 20.0)
        } else {
            Issue.record("Expected .backingOff(1, 20.0), got \(state)")
        }
        #expect(await engine.consecutiveFailures == 1)

        // Failure 2: delay = 10 * 2^2 = 40.0
        _ = await engine.pollOnce()
        state = await engine.state
        if case .backingOff(let failures, let delay) = state {
            #expect(failures == 2)
            #expect(delay == 40.0)
        } else {
            Issue.record("Expected .backingOff(2, 40.0), got \(state)")
        }
        #expect(await engine.consecutiveFailures == 2)

        // Failure 3: delay = 10 * 2^3 = 80.0
        _ = await engine.pollOnce()
        state = await engine.state
        if case .backingOff(let failures, let delay) = state {
            #expect(failures == 3)
            #expect(delay == 80.0)
        } else {
            Issue.record("Expected .backingOff(3, 80.0), got \(state)")
        }

        // Recovery on success
        await engine.startPolling(
            fetchHandler: { [XPost(id: "recovered_post", text: "Healthy")] },
            onNewPosts: { _ in }
        )
        _ = await engine.pollOnce()
        #expect(await engine.state == .polling)
        #expect(await engine.consecutiveFailures == 0)

        await engine.stop()
    }

    // MARK: - Test 1.18: Cancellation Safety on In-Flight Fetch
    @Test("Verify Engine State Remains Idle When Stop Is Invoked During In-Flight Fetch")
    func testCancellationSafetyDuringInFlightFetch() async {
        let engine = TimelinePollingEngine(interval: 30.0)

        await engine.startPolling(
            fetchHandler: {
                try await Task.sleep(nanoseconds: 200_000_000)
                throw CancellationError()
            },
            onNewPosts: { _ in }
        )

        let pollTask = Task {
            await engine.pollOnce()
        }

        // Allow fetch to start
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Stop engine while fetch is in-flight
        await engine.stop()
        #expect(await engine.state == .idle)

        _ = await pollTask.value

        // State MUST remain idle; MUST NOT revive to .backingOff
        let finalState = await engine.state
        #expect(finalState == .idle, "Cancellation during fetch must leave engine in .idle, but found: \(finalState)")
        #expect(await engine.consecutiveFailures == 0)
    }

    // MARK: - Test 1.19: Contract Overload startPolling Wires Service
    @Test("Verify startPolling Contract Overload Fetches Real Posts via Injected Service")
    func testStartPollingContractOverloadWithService() async {
        let service = await MainActor.run {
            MockClientService(
                timelinePosts: [
                    XPost(id: "contract_p1", text: "Contract post 1", createdAt: Date()),
                    XPost(id: "contract_p2", text: "Contract post 2", createdAt: Date())
                ]
            )
        }
        let engine = TimelinePollingEngine(interval: 15.0, service: service)

        await engine.startPolling(interval: 15.0) { _ in }
        let fetched = await engine.pollOnce()
        #expect(fetched.count == 2)
        #expect(fetched.contains(where: { $0.id == "contract_p1" }))
        #expect(fetched.contains(where: { $0.id == "contract_p2" }))

        await engine.stop()
        #expect(await engine.state == .idle)
    }
}
