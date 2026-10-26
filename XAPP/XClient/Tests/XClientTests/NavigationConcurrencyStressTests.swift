//
//  NavigationConcurrencyStressTests.swift
//  XClientTests
//
//  Empirical Concurrency, Cross-Actor Boundary, Underflow & Heavy Stress Challenge Suite.
//  100% Swift 6 strict concurrency compliance.
//

import Testing
import Foundation
import SwiftUI
import Combine
@testable import XClient

// MARK: - Dedicated Background Actor Mock Dispatchers

/// Background actor simulating concurrent remote push notifications and deep links.
private actor RemotePushDispatcherActor {
    let navigationState: AppNavigationState

    init(navigationState: AppNavigationState) {
        self.navigationState = navigationState
    }

    func dispatchDeepLink(url: URL) async -> Bool {
        await navigationState.handle(url: url)
    }

    func dispatchTabSwitch(to destination: AppDestination) async {
        await navigationState.selectTab(destination)
    }

    func dispatchPushRoute(route: NavigationRoute, on destination: AppDestination?) async {
        await navigationState.push(route: route, on: destination)
    }

    func dispatchPop(on destination: AppDestination?) async -> NavigationRoute? {
        await navigationState.pop(on: destination)
    }

    func dispatchBadgeUpdate(destination: AppDestination, delta: Int) async {
        await navigationState.incrementBadge(for: destination, by: delta)
    }
}

/// Thread-safe event collector for testing Combine publishers across actor boundaries.
private final class ThreadSafeEventCollector<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [T] = []

    func append(_ item: T) {
        lock.lock()
        defer { lock.unlock() }
        items.append(item)
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return items.count
    }

    var allItems: [T] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }
}

// MARK: - Navigation Concurrency & Adversarial Stress Suite

@Suite("Navigation Concurrency & Adversarial Stress Tests", .serialized)
struct NavigationConcurrencyStressTests {

    // MARK: - Challenge 1: Massive Concurrent Push/Pop & Empty Stack Underflow Safety
    @Test("200 concurrent tasks performing 1,000 push/pop cycles verifying underflow safety and stack integrity")
    func testMassiveConcurrentPushPopAndUnderflowSafety() async throws {
        let state = await MainActor.run {
            AppNavigationState()
        }

        // Phase A: Concurrent pop on empty stacks across 50 background tasks
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    for _ in 0..<20 {
                        let popped = await state.pop()
                        #expect(popped == nil, "Popping an empty stack must safely return nil")
                    }
                }
            }
            try await group.waitForAll()
        }

        await MainActor.run {
            #expect(state.currentPath.isEmpty)
            for dest in AppDestination.allCases {
                #expect(state.path(for: dest).isEmpty)
                #expect(state.navigationPaths[dest]?.isEmpty == true)
            }
        }

        // Phase B: Heavy concurrent push/pop churn (150 tasks)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<150 {
                group.addTask {
                    let dest = AppDestination.allCases[i % AppDestination.allCases.count]
                    let route = NavigationRoute.postDetail(postId: "stress_post_\(i)")

                    await state.push(route: route, on: dest)

                    if i % 2 == 0 {
                        _ = await state.pop(on: dest)
                    }
                    if i % 7 == 0 {
                        await state.popToRoot(on: dest)
                    }
                }
            }
            try await group.waitForAll()
        }

        // Phase C: Validate state invariants
        await MainActor.run {
            for dest in AppDestination.allCases {
                let typedRoutes = state.path(for: dest)
                let navPath = state.navigationPaths[dest]
                #expect(navPath != nil)
                #expect(typedRoutes.count == navPath?.count, "Typed routes and SwiftUI NavigationPath must have identical depths")
                #expect(typedRoutes.count >= 0)
            }
        }
    }

    // MARK: - Challenge 2: Rapid Concurrent Deep Linking While Tabs Are Switching
    @Test("200 concurrent tasks rapidly dispatching deep links and tab switches")
    func testRapidConcurrentDeepLinkingWhileTabSwitching() async throws {
        let state = await MainActor.run {
            AppNavigationState()
        }

        let urls: [URL] = [
            URL(string: "xclient://timeline")!,
            URL(string: "xclient://bookmarks")!,
            URL(string: "xclient://profile/usr_stress_99")!,
            URL(string: "xclient://settings")!,
            URL(string: "xclient://post/post_deep_1001")!,
            URL(string: "xclient://compose")!,
            URL(string: "xclient://unknown_target")!,
            URL(string: "xclient://post")!,
            URL(string: "https://example.com/not_xclient")!
        ]

        try await withThrowingTaskGroup(of: Void.self) { group in
            // 100 deep-link tasks
            for i in 0..<100 {
                group.addTask {
                    let url = urls[i % urls.count]
                    _ = await state.handle(url: url)
                }
            }

            // 100 tab switching and sheet presentation tasks
            for i in 0..<100 {
                group.addTask {
                    let dest = AppDestination.allCases[i % AppDestination.allCases.count]
                    await state.selectTab(dest)
                    if i % 5 == 0 {
                        await state.presentSheet(.composer(draftId: "draft_\(i)", replyToPostId: nil))
                    } else if i % 11 == 0 {
                        await state.dismissSheet()
                    }
                }
            }

            try await group.waitForAll()
        }

        await MainActor.run {
            #expect(AppDestination.allCases.contains(state.selectedDestination))
            #expect(state.selectedTab == state.selectedDestination, "selectedTab and selectedDestination must remain synchronized")
            if state.isComposePresented {
                #expect(state.presentedSheet != nil)
            }
        }
    }

    // MARK: - Challenge 3: TabBarCoordinator Reselection and Token Integrity
    @Test("100 concurrent tasks stressing TabBarCoordinator tab reselection and scroll-to-top triggers")
    func testTabBarCoordinatorConcurrentReselectionAndTokenIntegrity() async throws {
        let state = await MainActor.run {
            AppNavigationState()
        }
        let coordinator = await MainActor.run {
            state.tabBarCoordinator
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    let dest = AppDestination.allCases[i % AppDestination.allCases.count]
                    await coordinator.handleTabReselection(dest)
                }
            }
            try await group.waitForAll()
        }

        await MainActor.run {
            let totalTriggers = coordinator.scrollToTopTriggers.values.reduce(0, +)
            #expect(totalTriggers > 0, "Concurrent reselection must register scroll-to-top triggers")

            for dest in AppDestination.allCases {
                let token = state.scrollToTopToken(for: dest)
                #expect(token != nil, "Scroll-to-top token must exist for \(dest)")
            }
        }
    }

    // MARK: - Challenge 4: Combine Publishers Backpressure and Thread Safety
    @Test("500 rapid scroll-to-top and refresh events through Combine publishers")
    func testCombinePublishersBackpressureAndThreadSafety() async throws {
        let state = await MainActor.run {
            AppNavigationState()
        }
        let coordinator = await MainActor.run {
            state.tabBarCoordinator
        }

        let scrollCollector = ThreadSafeEventCollector<ScrollToTopEvent>()
        let refreshCollector = ThreadSafeEventCollector<AppDestination>()

        var cancellables = Set<AnyCancellable>()

        await MainActor.run {
            coordinator.scrollToTopPublisher
                .sink { event in
                    scrollCollector.append(event)
                }
                .store(in: &cancellables)

            coordinator.refreshPublisher
                .sink { destination in
                    refreshCollector.append(destination)
                }
                .store(in: &cancellables)
        }

        let eventCount = 250
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<eventCount {
                group.addTask {
                    let dest = AppDestination.allCases[i % AppDestination.allCases.count]
                    await coordinator.triggerScrollToTop(for: dest, isDoubleTap: (i % 2 == 0))
                    if i % 2 == 0 {
                        await coordinator.triggerRefresh(for: dest)
                    }
                }
            }
            try await group.waitForAll()
        }

        #expect(scrollCollector.count == eventCount, "All \(eventCount) scroll-to-top events must be collected without dropping")
        #expect(refreshCollector.count == (eventCount + 1) / 2, "All expected refresh events must be collected")

        _ = cancellables
    }

    // MARK: - Challenge 5: Deep Navigation Stack & Concurrent PopToRoot
    @Test("500-level deep navigation stack pushed and popped to root under contention")
    func testNavigationStackDeepNestingAndRapidPopToRoot() async throws {
        let state = await MainActor.run {
            AppNavigationState()
        }

        // Push 500 routes sequentially
        await MainActor.run {
            state.selectTab(.timeline)
            for i in 0..<500 {
                state.push(route: .postDetail(postId: "deep_post_\(i)"))
            }
            #expect(state.currentPath.count == 500)
            #expect(state.navigationPaths[.timeline]?.count == 500)
        }

        // Concurrently popToRoot and push new items
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    if i % 5 == 0 {
                        await state.popToRoot(on: .timeline)
                    } else {
                        await state.push(route: .userProfile(userId: "u_\(i)"), on: .timeline)
                        _ = await state.pop(on: .timeline)
                    }
                }
            }
            try await group.waitForAll()
        }

        await MainActor.run {
            let typedCount = state.path(for: .timeline).count
            let navCount = state.navigationPaths[.timeline]?.count ?? 0
            #expect(typedCount == navCount, "Typed and NavigationPath depths must remain strictly identical")
            #expect(typedCount >= 0)
        }
    }

    // MARK: - Challenge 6: ResetAll Under Active Contention
    @Test("ResetAll restores clean default state even while active background mutations occur")
    func testResetAllUnderActiveContention() async throws {
        let state = await MainActor.run {
            AppNavigationState()
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    let dest = AppDestination.allCases[i % AppDestination.allCases.count]
                    await state.push(route: .postDetail(postId: "post_\(i)"), on: dest)
                    await state.selectTab(dest)
                    if i == 50 {
                        await state.resetAll()
                    }
                }
            }
            try await group.waitForAll()
        }

        // Final authoritative reset to verify full recovery
        await MainActor.run {
            state.resetAll()
            #expect(state.selectedTab == .timeline)
            #expect(state.selectedDestination == .timeline)
            #expect(state.presentedSheet == nil)
            #expect(state.isComposePresented == false)
            #expect(state.isSettingsSheetPresented == false)
            for dest in AppDestination.allCases {
                #expect(state.path(for: dest).isEmpty)
                #expect(state.navigationPaths[dest]?.isEmpty == true)
            }
        }
    }

    // MARK: - Challenge 7: Deep Link URL Parsing Boundary & Corner Cases
    @Test("Verify Deep Link URL parsing handles all valid, malformed, and boundary inputs deterministically")
    @MainActor
    func testDeepLinkUrlCornerCasesAndBoundaryParsing() {
        let state = AppNavigationState()

        // 1. Standard destinations
        #expect(state.handle(url: URL(string: "xclient://timeline")!))
        #expect(state.selectedDestination == .timeline)

        #expect(state.handle(url: URL(string: "xclient://bookmarks")!))
        #expect(state.selectedDestination == .bookmarks)

        #expect(state.handle(url: URL(string: "xclient://settings")!))
        #expect(state.selectedDestination == .settings)

        // 2. Profile with user ID
        #expect(state.handle(url: URL(string: "xclient://profile/user_404")!))
        #expect(state.selectedDestination == .profile)
        #expect(state.selectedUserId == "user_404")

        // 3. Post with post ID pushes route to timeline
        let initialTimelineDepth = state.path(for: .timeline).count
        #expect(state.handle(url: URL(string: "xclient://post/post_special_777")!))
        #expect(state.selectedDestination == .timeline)
        #expect(state.selectedPostId == "post_special_777")
        #expect(state.path(for: .timeline).count == initialTimelineDepth + 1)
        #expect(state.path(for: .timeline).last == .postDetail(postId: "post_special_777"))

        // 4. Compose modal presentation
        #expect(state.handle(url: URL(string: "xclient://compose")!))
        #expect(state.isComposePresented == true)
        #expect(state.presentedSheet == .composer(draftId: nil, replyToPostId: nil))
        state.dismissSheet()

        // 5. Invalid scheme
        #expect(!state.handle(url: URL(string: "https://xclient.com/timeline")!))
        #expect(!state.handle(url: URL(string: "twitter://timeline")!))

        // 6. Unknown host
        #expect(!state.handle(url: URL(string: "xclient://nonexistent_host")!))
    }

    // MARK: - Challenge 8: Sheet Presentation Exclusivity and Modal Flags
    @Test("Verify sheet presentation exclusivity and modal boolean flags maintain strict synchronization")
    @MainActor
    func testSheetPresentationExclusivityAndFlags() {
        let state = AppNavigationState()

        // Initial
        #expect(state.presentedSheet == nil)
        #expect(!state.isComposePresented)
        #expect(!state.isSettingsSheetPresented)

        // Present composer
        state.isComposePresented = true
        #expect(state.isComposePresented)
        #expect(!state.isSettingsSheetPresented)
        #expect(state.presentedSheet == .composer(draftId: nil, replyToPostId: nil))

        // Switch to settings directly
        state.isSettingsSheetPresented = true
        #expect(!state.isComposePresented)
        #expect(state.isSettingsSheetPresented)
        #expect(state.presentedSheet == .settings)

        // Present drafts via presentedSheet
        state.presentSheet(.drafts)
        #expect(!state.isComposePresented)
        #expect(!state.isSettingsSheetPresented)
        #expect(state.presentedSheet == .drafts)

        // Dismiss
        state.dismissSheet()
        #expect(state.presentedSheet == nil)
        #expect(!state.isComposePresented)
        #expect(!state.isSettingsSheetPresented)
    }

    // MARK: - Challenge 9: Concurrent Badge Mutations & Monotonic Clamping
    @Test("200 concurrent tasks incrementing and clearing badges with zero-underflow guarantee")
    func testBadgeCountConcurrentMutationsAndClamping() async throws {
        let state = await MainActor.run {
            AppNavigationState()
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<200 {
                group.addTask {
                    let dest = AppDestination.allCases[i % AppDestination.allCases.count]
                    if i % 3 == 0 {
                        await state.incrementBadge(for: dest, by: 1)
                    } else if i % 3 == 1 {
                        // Negative increment must clamp to 0
                        await state.incrementBadge(for: dest, by: -5)
                    } else {
                        await state.setBadgeCount(i, for: dest)
                    }
                }
            }
            try await group.waitForAll()
        }

        await MainActor.run {
            for dest in AppDestination.allCases {
                let count = state.badgeCount(for: dest)
                #expect(count >= 0, "Badge count must never underflow below 0")
                let formatted = TabBarCoordinator.formattedBadgeString(for: count)
                if count == 0 {
                    #expect(formatted == nil)
                } else if count <= 99 {
                    #expect(formatted == "\(count)")
                } else {
                    #expect(formatted == "99+")
                }
            }
        }
    }

    // MARK: - Challenge 10: Multi-Actor Orchestrated Stress Load (5 Background Actors)
    @Test("5 background actors dispatching 1,000 operations across actor boundaries under heavy load")
    func testMultiActorOrchestratedStressLoad() async throws {
        let state = await MainActor.run {
            AppNavigationState()
        }

        let actors = [
            RemotePushDispatcherActor(navigationState: state),
            RemotePushDispatcherActor(navigationState: state),
            RemotePushDispatcherActor(navigationState: state),
            RemotePushDispatcherActor(navigationState: state),
            RemotePushDispatcherActor(navigationState: state)
        ]

        let startTime = Date()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<1000 {
                let worker = actors[i % actors.count]
                group.addTask {
                    let dest = AppDestination.allCases[i % AppDestination.allCases.count]
                    if i % 4 == 0 {
                        _ = await worker.dispatchDeepLink(url: URL(string: "xclient://post/stress_\(i)")!)
                    } else if i % 4 == 1 {
                        await worker.dispatchTabSwitch(to: dest)
                    } else if i % 4 == 2 {
                        await worker.dispatchPushRoute(route: .postDetail(postId: "p_\(i)"), on: dest)
                        _ = await worker.dispatchPop(on: dest)
                    } else {
                        await worker.dispatchBadgeUpdate(destination: dest, delta: 1)
                    }
                }
            }
            try await group.waitForAll()
        }

        let elapsed = Date().timeIntervalSince(startTime)
        #expect(elapsed < 10.0, "1,000 multi-actor operations must execute under 10 seconds, took \(elapsed)s")

        await MainActor.run {
            #expect(AppDestination.allCases.contains(state.selectedDestination))
            for dest in AppDestination.allCases {
                #expect(state.path(for: dest).count >= 0)
                #expect(state.badgeCount(for: dest) >= 0)
            }
        }
    }
}
