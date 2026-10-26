//
//  TimelineStressTests.swift
//  XClientTests
//
//  Adversarial Empirical Stress Test Suite for Milestone 3:
//  - Concurrency stress on TimelinePollingEngine lifecycle & error backoff
//  - Viewport invariance and unread buffer accumulation & ordering
//  - Cursor-based pagination boundary deduplication and concurrency throttling
//  - TabBarCoordinator reselection timing (<0.35s vs >=0.35s) and deep stack handling
//  100% Swift 6 strict concurrency compliance.
//

import Testing
import Foundation
import SwiftUI
import Combine
import XKitModels
import XKitAPI
@testable import XClient

@Suite("Milestone 3: Empirical Timeline & Concurrency Stress Tests", .serialized)
struct TimelineStressTests {

    // MARK: - Section 1: TimelinePollingEngine Concurrency Stress

    @Test("Challenge 1.1: Rapid Concurrent Lifecycle Mutations on TimelinePollingEngine")
    func testTimelinePollingEngineLifecycleStress() async throws {
        let engine = TimelinePollingEngine(interval: 0.1)

        // 50 parallel asynchronous tasks hammering start, pause, resume, and stop
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    switch i % 4 {
                    case 0:
                        await engine.startPolling(
                            interval: 0.05,
                            initialKnownIds: ["p_\(i)"],
                            fetchHandler: { [XPost(id: "poll_\(i)", text: "Poll \(i)")] },
                            onNewPosts: { _ in }
                        )
                    case 1:
                        await engine.pause()
                    case 2:
                        await engine.resume()
                    case 3:
                        await engine.stop()
                    default:
                        break
                    }
                }
            }
            await group.waitForAll()
        }

        // Clean termination
        await engine.stop()
        let finalState = await engine.state
        #expect(finalState == .idle, "Engine did not reach idle state cleanly: \(finalState)")
        let failures = await engine.consecutiveFailures
        #expect(failures == 0, "Failures must be reset to 0 after stop")
    }

    @Test("Challenge 1.2: Exponential Error Backoff Policy Progression")
    func testBackoffPolicyProgression() {
        let policy = TimelinePollingEngine.BackoffPolicy(baseInterval: 10.0, multiplier: 2.0, maxInterval: 100.0)
        #expect(policy.calculateDelay(forFailures: 0) == 10.0)
        #expect(policy.calculateDelay(forFailures: 1) == 20.0)
        #expect(policy.calculateDelay(forFailures: 2) == 40.0)
        #expect(policy.calculateDelay(forFailures: 3) == 80.0)
        #expect(policy.calculateDelay(forFailures: 4) == 100.0)
        #expect(policy.calculateDelay(forFailures: 10) == 100.0)
    }

    @Test("Challenge 1.3: Polling Engine State Recovery After Failures")
    func testPollingEngineErrorStateRecovery() async {
        struct TestNetworkError: Error {}
        let engine = TimelinePollingEngine(interval: 30.0)
        await engine.startPolling(
            fetchHandler: { throw TestNetworkError() },
            onNewPosts: { _ in }
        )

        _ = await engine.pollOnce()
        var state = await engine.state
        if case .backingOff(let count, let delay) = state {
            #expect(count == 1)
            #expect(delay == 45.0)
        } else {
            Issue.record("Expected .backingOff after poll 1 failure, got \(state)")
        }

        _ = await engine.pollOnce()
        state = await engine.state
        if case .backingOff(let count, let delay) = state {
            #expect(count == 2)
            #expect(delay == 67.5)
        } else {
            Issue.record("Expected .backingOff after poll 2 failure, got \(state)")
        }

        // Recovery on successful poll
        await engine.startPolling(
            fetchHandler: { [XPost(id: "recov_1", text: "Recovered")] },
            onNewPosts: { _ in }
        )
        _ = await engine.pollOnce()
        state = await engine.state
        #expect(state == .polling)
        #expect(await engine.consecutiveFailures == 0)
        await engine.stop()
    }

    @Test("Challenge 1.4: Polling Engine State Anti-Revival on In-Flight Cancellation")
    func testPollingEngineAntiRevivalOnCancellation() async {
        struct TestNetworkError: Error {}
        let engine = TimelinePollingEngine(interval: 10.0)
        await engine.startPolling(
            fetchHandler: {
                try await Task.sleep(nanoseconds: 50_000_000)
                throw TestNetworkError()
            },
            onNewPosts: { _ in }
        )

        let pollTask = Task { await engine.pollOnce() }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await engine.stop()
        #expect(await engine.state == .idle)

        _ = await pollTask.value
        let stateAfterError = await engine.state
        #expect(stateAfterError == .idle, "Cancellation during in-flight fetch must not revive to .backingOff")
        #expect(await engine.consecutiveFailures == 0)
    }

    // MARK: - Section 2: Viewport Invariance & Unread Buffer Integrity

    @Test("Challenge 2.1: Streaming 50+ Polled Posts Preserves Viewport Invariance")
    @MainActor
    func testStreamingPostsViewportInvariance() async {
        let provider = MockDataProvider()
        let service = MockClientService(
            currentUser: provider.currentUser,
            timelinePosts: Array(provider.timelinePosts.prefix(10)),
            users: provider.users
        )
        let navState = AppNavigationState(initialDestination: .timeline)
        let vm = TimelineViewModel(service: service, navigationState: navState)

        await vm.fetchTimeline()
        #expect(vm.posts.count == 10)
        #expect(vm.unreadCount == 0)
        #expect(vm.unreadBuffer.isEmpty)

        let initialSnapshot = vm.posts.map(\.id)
        let now = Date()

        // Stream 60 posts across 5 batches
        for batch in 0..<5 {
            let polledBatch = (0..<12).map { item in
                let id = "polled_stream_b\(batch)_i\(item)"
                let postDate = now.addingTimeInterval(Double((batch * 12 + item + 1) * 10))
                return XPost(id: id, text: "Polled \(id)", authorId: provider.currentUser.id, createdAt: postDate)
            }
            vm.handleNewPolledPosts(polledBatch)
        }

        // Visible feed must remain unchanged
        let currentSnapshot = vm.posts.map(\.id)
        #expect(currentSnapshot == initialSnapshot, "Visible posts array mutated while user is viewing feed!")
        #expect(vm.posts.count == 10)

        // Unread buffer and tab badge must reflect exactly 60
        #expect(vm.unreadCount == 60)
        #expect(vm.unreadBuffer.count == 60)
        #expect(navState.badgeCounts[.timeline] == 60)

        // Flush buffer
        vm.flushUnreadBuffer()
        #expect(vm.unreadCount == 0)
        #expect(vm.unreadBuffer.isEmpty)
        #expect(navState.badgeCounts[.timeline] == 0)
        #expect(vm.posts.count == 70)
    }

    @Test("Challenge 2.2: Reverse-Chronological Ordering Invariant on Flushed Posts")
    @MainActor
    func testFlushUnreadBufferReverseChronologicalInvariant() async {
        let provider = MockDataProvider()
        let service = MockClientService(
            currentUser: provider.currentUser,
            timelinePosts: Array(provider.timelinePosts.prefix(5)),
            users: provider.users
        )
        let vm = TimelineViewModel(service: service)
        await vm.fetchTimeline()

        // 1. Polled items arriving in ascending order: itemA (+30s), itemB (+60s), itemC (+90s)
        let now = Date()
        let items = [
            XPost(id: "ord_1", text: "Order 1", authorId: provider.currentUser.id, createdAt: now.addingTimeInterval(30)),
            XPost(id: "ord_2", text: "Order 2", authorId: provider.currentUser.id, createdAt: now.addingTimeInterval(60)),
            XPost(id: "ord_3", text: "Order 3", authorId: provider.currentUser.id, createdAt: now.addingTimeInterval(90))
        ]
        vm.handleNewPolledPosts(items)
        vm.flushUnreadBuffer()

        // Feed MUST be in strict reverse-chronological order (newest first)
        for i in 0..<(vm.posts.count - 1) {
            let current = vm.posts[i].createdAt
            let next = vm.posts[i + 1].createdAt
            #expect(current >= next, "DEFECT: Post at index \(i) (\(vm.posts[i].id)) is older than post at \(i+1) (\(vm.posts[i+1].id))!")
        }

        // 2. Multi-batch shuffled arrival with identical timestamps tie-breaking
        let shuffledDate = now.addingTimeInterval(200)
        let batchA = [
            XPost(id: "shuf_3", text: "Shuf 3", authorId: provider.currentUser.id, createdAt: shuffledDate.addingTimeInterval(30)),
            XPost(id: "shuf_1", text: "Shuf 1", authorId: provider.currentUser.id, createdAt: shuffledDate.addingTimeInterval(10))
        ]
        let batchB = [
            XPost(id: "shuf_4", text: "Shuf 4", authorId: provider.currentUser.id, createdAt: shuffledDate.addingTimeInterval(40)),
            XPost(id: "shuf_2", text: "Shuf 2", authorId: provider.currentUser.id, createdAt: shuffledDate.addingTimeInterval(20)),
            XPost(id: "shuf_tie_b", text: "Tie B", authorId: provider.currentUser.id, createdAt: shuffledDate.addingTimeInterval(50)),
            XPost(id: "shuf_tie_a", text: "Tie A", authorId: provider.currentUser.id, createdAt: shuffledDate.addingTimeInterval(50))
        ]
        vm.handleNewPolledPosts(batchA)
        vm.handleNewPolledPosts(batchB)
        vm.flushUnreadBuffer()

        for i in 0..<(vm.posts.count - 1) {
            let current = vm.posts[i].createdAt
            let next = vm.posts[i + 1].createdAt
            #expect(current >= next, "DEFECT: Multi-batch flushed post at \(i) is older than post at \(i+1)!")
            if current == next {
                #expect(vm.posts[i].id >= vm.posts[i + 1].id, "DEFECT: Tie-breaker failed on identical timestamps: \(vm.posts[i].id) vs \(vm.posts[i+1].id)")
            }
        }
    }

    @Test("Challenge 2.3: Intra-Batch Duplicate Post Ingestion Defense")
    @MainActor
    func testIntraBatchDuplicateIngestion() {
        let vm = TimelineViewModel(service: MockClientService())
        let duplicateBatch = [
            XPost(id: "intra_dup_1", text: "First copy", createdAt: Date()),
            XPost(id: "intra_dup_1", text: "Second duplicate copy", createdAt: Date()),
            XPost(id: "intra_novel_2", text: "Novel", createdAt: Date()),
            XPost(id: "intra_dup_3", text: "Dup 3 first", createdAt: Date()),
            XPost(id: "intra_dup_3", text: "Dup 3 second", createdAt: Date()),
            XPost(id: "intra_dup_3", text: "Dup 3 third", createdAt: Date())
        ]
        vm.handleNewPolledPosts(duplicateBatch)

        let bufferIds = vm.unreadBuffer.map(\.id)
        let uniqueBufferIds = Set(bufferIds)
        #expect(bufferIds.count == uniqueBufferIds.count, "DEFECT: handleNewPolledPosts allowed intra-batch duplicate IDs into unreadBuffer!")
        #expect(bufferIds.count == 3, "Expected exactly 3 unique posts in unread buffer, got \(bufferIds.count)")

        // Second batch containing repeated IDs from unreadBuffer and visible feed
        let secondBatch = [
            XPost(id: "intra_dup_1", text: "Repeat from unread", createdAt: Date()),
            XPost(id: "intra_novel_4", text: "Novel 4", createdAt: Date()),
            XPost(id: "intra_novel_4", text: "Novel 4 dup", createdAt: Date())
        ]
        vm.handleNewPolledPosts(secondBatch)
        #expect(vm.unreadBuffer.count == 4, "Expected exactly 4 unique posts in unreadBuffer after second batch")

        vm.flushUnreadBuffer()
        let postIds = vm.posts.map(\.id)
        let uniquePostIds = Set(postIds)
        #expect(postIds.count == uniquePostIds.count, "DEFECT: Visible feed contains duplicate IDs after flush!")
        #expect(postIds.count == 4)
    }

    // MARK: - Section 3: Pagination Cursor Traversal Stress

    @Test("Challenge 3.1: Sequential Pagination Boundary Overlap Filtering")
    @MainActor
    func testPaginationBoundaryOverlapDeduplication() async {
        let provider = MockDataProvider()
        let p1 = Array(provider.timelinePosts.prefix(5))
        // Server boundary repeat: page 2 includes the last 2 posts of page 1
        let p2 = [p1[3], p1[4]] + Array(provider.timelinePosts[5..<8])

        let service = MockClientService(
            currentUser: provider.currentUser,
            timelinePosts: p1,
            users: provider.users
        )
        let vm = TimelineViewModel(service: service)
        await vm.fetchTimeline()
        #expect(vm.posts.count == 5)

        // Inject page 2
        service.timelinePosts = p1 + p2
        await vm.loadMore()

        let ids = vm.posts.map(\.id)
        let uniqueIds = Set(ids)
        #expect(ids.count == uniqueIds.count, "Duplicate IDs found across pagination boundary!")
    }

    @Test("Challenge 3.2: Concurrent LoadMore Throttling")
    @MainActor
    func testConcurrentLoadMoreThrottling() async {
        let provider = MockDataProvider()
        let service = MockClientService(
            currentUser: provider.currentUser,
            timelinePosts: provider.timelinePosts,
            users: provider.users
        )
        let vm = TimelineViewModel(service: service)
        await vm.fetchTimeline()

        // Launch 5 concurrent loadMore calls
        async let l1: () = vm.loadMore()
        async let l2: () = vm.loadMore()
        async let l3: () = vm.loadMore()
        async let l4: () = vm.loadMore()
        async let l5: () = vm.loadMore()
        _ = await (l1, l2, l3, l4, l5)

        #expect(vm.isLoadingMore == false)
        let ids = vm.posts.map(\.id)
        #expect(ids.count == Set(ids).count, "Concurrent loadMore created duplicate post entries!")
    }

    // MARK: - Section 4: TabBarCoordinator Integration & Reselection Timing

    @Test("Challenge 4.1: TabBarCoordinator Slow vs Rapid Reselection Timing Threshold")
    @MainActor
    func testTabBarCoordinatorReselectionTiming() {
        let navState = AppNavigationState(initialDestination: .timeline)
        let coordinator = navState.tabBarCoordinator

        var refreshCount = 0
        var scrollToTopEvents: [ScrollToTopEvent] = []

        let c1 = coordinator.refreshPublisher.sink { dest in
            if dest == .timeline { refreshCount += 1 }
        }
        let c2 = coordinator.scrollToTopPublisher.sink { event in
            scrollToTopEvents.append(event)
        }

        let t0 = Date()
        coordinator.handleTabSelection(.timeline, date: t0)

        // Slow tap (>=0.35s) -> Scroll to top ONLY, no refresh
        let t1 = t0.addingTimeInterval(0.50)
        coordinator.handleTabReselection(.timeline, date: t1)
        #expect(scrollToTopEvents.count == 1)
        #expect(scrollToTopEvents.last?.isDoubleTap == false)
        #expect(refreshCount == 0)

        // Rapid tap (<0.35s) -> Scroll to top AND refresh
        let t2 = t1.addingTimeInterval(0.15)
        coordinator.handleTabReselection(.timeline, date: t2)
        #expect(scrollToTopEvents.count == 2)
        #expect(scrollToTopEvents.last?.isDoubleTap == true)
        #expect(refreshCount == 1)

        c1.cancel()
        c2.cancel()
    }

    @Test("Challenge 4.2: Deep Navigation Stack Reselection Pops to Root")
    @MainActor
    func testDeepNavigationStackReselectionBehavior() {
        let navState = AppNavigationState(initialDestination: .timeline)
        let coordinator = navState.tabBarCoordinator

        var refreshCount = 0
        var scrollToTopCount = 0

        let c1 = coordinator.refreshPublisher.sink { _ in refreshCount += 1 }
        let c2 = coordinator.scrollToTopPublisher.sink { _ in scrollToTopCount += 1 }

        navState.push(route: .postDetail(postId: "p123"), on: .timeline)
        #expect(navState.path(for: .timeline).count == 1)

        coordinator.handleTabReselection(.timeline, date: Date())

        #expect(navState.path(for: .timeline).isEmpty, "Deep stack must be popped to root!")
        #expect(scrollToTopCount == 0, "Pop to root must not trigger scroll-to-top event")
        #expect(refreshCount == 0, "Pop to root must not trigger feed refresh")

        c1.cancel()
        c2.cancel()
    }
}
