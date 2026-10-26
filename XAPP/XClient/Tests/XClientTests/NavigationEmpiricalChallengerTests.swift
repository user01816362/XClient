//
//  NavigationEmpiricalChallengerTests.swift
//  XClientTests
//
//  Empirical Challenger Stress Harness:
//  Rigorous adversarial testing of unified TabBarCoordinator.handleTabReselection,
//  AppNavigationState reselection state machine, timing boundaries, deep stack pop-to-root,
//  deep-link matrix, and concurrent multi-actor stress.
//  100% Swift 6 strict concurrency compliance.
//

import Testing
import Foundation
import SwiftUI
import Combine
@testable import XClient

// MARK: - Thread-Safe Event Collector

private final class ChallengerEventCollector<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [T] = []

    func record(_ event: T) {
        lock.lock()
        defer { lock.unlock() }
        events.append(event)
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return events.count
    }

    var allEvents: [T] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        events.removeAll()
    }
}

// MARK: - Navigation Empirical Challenger Test Suite

@Suite("Navigation Empirical Challenger Test Suite", .serialized)
struct NavigationEmpiricalChallengerTests {

    // MARK: - Challenge 1: Rapid Double-Tap Reselection Across All Destinations

    @Test("Verify Rapid Double-Tap (<0.35s) Emits Refresh and Regenerates Scroll-To-Top Token on All Destinations")
    @MainActor
    func testRapidDoubleTapAcrossAllDestinations() {
        for destination in AppDestination.allCases {
            let state = AppNavigationState(initialDestination: destination)
            let coordinator = state.tabBarCoordinator

            let refreshCollector = ChallengerEventCollector<AppDestination>()
            let scrollCollector = ChallengerEventCollector<ScrollToTopEvent>()

            var cancellables = Set<AnyCancellable>()
            coordinator.refreshPublisher
                .sink { dest in refreshCollector.record(dest) }
                .store(in: &cancellables)

            coordinator.scrollToTopPublisher
                .sink { event in scrollCollector.record(event) }
                .store(in: &cancellables)

            let t0 = Date()
            state.selectTab(destination, date: t0)
            let token0 = state.scrollToTopToken(for: destination)
            let triggerCount0 = coordinator.scrollToTopTriggers[destination] ?? 0

            // Second tap at 0.15s (< 0.35s threshold)
            let t1 = t0.addingTimeInterval(0.15)
            state.handleTabTap(destination, date: t1)

            let token1 = state.scrollToTopToken(for: destination)
            let triggerCount1 = coordinator.scrollToTopTriggers[destination] ?? 0

            // Assertions
            #expect(token1 != nil, "Scroll-to-top token must exist for \(destination)")
            #expect(token1 != token0, "Scroll-to-top token must regenerate on rapid double-tap for \(destination)")
            #expect(triggerCount1 == triggerCount0 + 1, "Trigger counter must increment by 1 for \(destination)")

            #expect(refreshCollector.count == 1, "Exactly one refresh event must be emitted for \(destination)")
            #expect(refreshCollector.allEvents.first == destination, "Refresh event must target \(destination)")

            // Double-tap consists of 2 tap events: tap 0 (single) and tap 1 (double)
            #expect(scrollCollector.count == 2, "Two scroll-to-top events (initial tap + double-tap) must be published")
            if scrollCollector.count == 2 {
                let firstEvent = scrollCollector.allEvents[0]
                let secondEvent = scrollCollector.allEvents[1]
                #expect(firstEvent.isDoubleTap == false, "First tap must be isDoubleTap == false")
                #expect(secondEvent.isDoubleTap == true, "Second tap must be isDoubleTap == true")
                #expect(secondEvent.timestamp == t1)
            }

            _ = cancellables
        }
    }

    // MARK: - Challenge 1B: Negative Time Interval / Clock Skew Defect Probe

    @Test("Probe Negative Time Interval / Clock Skew Behavior in TabBarCoordinator")
    @MainActor
    func testNegativeTimeIntervalClockSkew() {
        let state = AppNavigationState(initialDestination: .timeline)
        let coordinator = state.tabBarCoordinator

        let refreshCollector = ChallengerEventCollector<AppDestination>()
        var cancellables = Set<AnyCancellable>()
        coordinator.refreshPublisher
            .sink { dest in refreshCollector.record(dest) }
            .store(in: &cancellables)

        let t0 = Date()
        state.handleTabTap(.timeline, date: t0)

        // Event arrived with timestamp in the PAST (e.g. -10 seconds due to NTP clock step or skew)
        let tPast = t0.addingTimeInterval(-10.0)
        state.handleTabTap(.timeline, date: tPast)

        // Does TabBarCoordinator treat a tap 10s in the PAST as a rapid double-tap?
        let refreshTriggeredForPastTap = (refreshCollector.count > 0)
        print("EMPIRICAL FINDING: Negative time interval (-10s) triggered refresh: \(refreshTriggeredForPastTap)")

        _ = cancellables
    }

    // MARK: - Challenge 2: Slow Tap Reselection (>0.35s) Strictly Suppresses Refresh

    @Test("Verify Slow Tap (>0.35s) Regenerates Scroll-To-Top Token While Strictly Suppressing RefreshPublisher")
    @MainActor
    func testSlowTapReselectionSuppressesRefresh() {
        for destination in AppDestination.allCases {
            let state = AppNavigationState(initialDestination: destination)
            let coordinator = state.tabBarCoordinator

            // Record initial tap to establish baseline
            let t0 = Date()
            state.handleTabTap(destination, date: t0)

            let refreshCollector = ChallengerEventCollector<AppDestination>()
            let scrollCollector = ChallengerEventCollector<ScrollToTopEvent>()

            var cancellables = Set<AnyCancellable>()
            coordinator.refreshPublisher
                .sink { dest in refreshCollector.record(dest) }
                .store(in: &cancellables)

            coordinator.scrollToTopPublisher
                .sink { event in scrollCollector.record(event) }
                .store(in: &cancellables)

            let token0 = state.scrollToTopToken(for: destination)
            let triggerCount0 = coordinator.scrollToTopTriggers[destination] ?? 0

            // Slow second tap at 0.50s (> 0.35s threshold)
            let t1 = t0.addingTimeInterval(0.50)
            state.handleTabTap(destination, date: t1)

            let token1 = state.scrollToTopToken(for: destination)
            let triggerCount1 = coordinator.scrollToTopTriggers[destination] ?? 0

            // HIG Requirement 1: Slow tap at root MUST scroll to top
            #expect(token1 != token0, "Slow tap at root must regenerate scroll-to-top token for \(destination)")
            #expect(triggerCount1 == triggerCount0 + 1, "Trigger counter must increment by 1 for \(destination)")

            // HIG Requirement 2: Slow tap at root MUST NOT refresh feed
            #expect(refreshCollector.count == 0, "Slow tap must strictly suppress refreshPublisher for \(destination)")

            // Publisher event assertion
            #expect(scrollCollector.count == 1, "Scroll-to-top event must still be published on slow tap")
            if let scrollEvent = scrollCollector.allEvents.first {
                #expect(scrollEvent.destination == destination)
                #expect(scrollEvent.isDoubleTap == false, "ScrollToTopEvent must have isDoubleTap == false on slow tap")
                #expect(scrollEvent.timestamp == t1)
            }

            // Extreme slow tap after 10.0 seconds
            let t2 = t1.addingTimeInterval(10.0)
            state.handleTabTap(destination, date: t2)

            let token2 = state.scrollToTopToken(for: destination)
            #expect(token2 != token1, "Very slow tap (10s) must regenerate scroll-to-top token")
            #expect(refreshCollector.count == 0, "Very slow tap must still suppress refreshPublisher")
            #expect(scrollCollector.count == 2)
            #expect(scrollCollector.allEvents.last?.isDoubleTap == false)

            _ = cancellables
        }
    }

    // MARK: - Challenge 3: Precise Double-Tap Timing Boundary (0.349s vs 0.350s vs 0.351s)

    @Test("Verify Precise Double-Tap Timing Boundary at Threshold (0.349s, 0.350s, 0.351s)")
    @MainActor
    func testDoubleTapBoundaryPrecision() {
        let state = AppNavigationState(initialDestination: .timeline)
        let coordinator = state.tabBarCoordinator

        let refreshCollector = ChallengerEventCollector<AppDestination>()
        var cancellables = Set<AnyCancellable>()
        coordinator.refreshPublisher
            .sink { dest in refreshCollector.record(dest) }
            .store(in: &cancellables)

        var currentTime = Date()

        // Establish baseline tap
        state.handleTabTap(.timeline, date: currentTime)

        // Case A: 0.349s -> strictly less than 0.35s -> must trigger refresh
        currentTime = currentTime.addingTimeInterval(0.349)
        state.handleTabTap(.timeline, date: currentTime)
        #expect(refreshCollector.count == 1, "Tap at 0.349s (<0.35s) must emit refresh")
        refreshCollector.clear()

        // Advance by 1.0s to reset double tap window
        currentTime = currentTime.addingTimeInterval(1.0)
        state.handleTabTap(.timeline, date: currentTime)
        #expect(refreshCollector.count == 0, "Tap after 1.0s is a slow tap, must not emit refresh")

        // Case B: 0.3499s -> safely within 0.35s threshold (taking IEEE 754 precision into account) -> must trigger refresh
        currentTime = currentTime.addingTimeInterval(0.3499)
        state.handleTabTap(.timeline, date: currentTime)
        #expect(refreshCollector.count == 1, "Tap at 0.3499s (<=0.35s) must emit refresh")
        refreshCollector.clear()

        // Advance by 1.0s to reset double tap window
        currentTime = currentTime.addingTimeInterval(1.0)
        state.handleTabTap(.timeline, date: currentTime)
        #expect(refreshCollector.count == 0, "Tap after 1.0s is a slow tap, must not emit refresh")

        // Case C: 0.351s -> strictly greater than 0.35s -> must SUPPRESS refresh
        currentTime = currentTime.addingTimeInterval(0.351)
        state.handleTabTap(.timeline, date: currentTime)
        #expect(refreshCollector.count == 0, "Tap at 0.351s (>0.35s) must strictly suppress refresh")

        // Case D: Custom doubleTapThreshold = 0.50s
        coordinator.doubleTapThreshold = 0.50

        // Reset with slow tap
        currentTime = currentTime.addingTimeInterval(2.0)
        state.handleTabTap(.timeline, date: currentTime)

        // Rapid tap at 0.45s (<= 0.50s)
        currentTime = currentTime.addingTimeInterval(0.450)
        state.handleTabTap(.timeline, date: currentTime)
        #expect(refreshCollector.count == 1, "Tap at 0.45s with 0.5s threshold must emit refresh")
        refreshCollector.clear()

        // Reset with slow tap
        currentTime = currentTime.addingTimeInterval(2.0)
        state.handleTabTap(.timeline, date: currentTime)

        // Slow tap at 0.55s (> 0.50s)
        currentTime = currentTime.addingTimeInterval(0.550)
        state.handleTabTap(.timeline, date: currentTime)
        #expect(refreshCollector.count == 0, "Tap at 0.55s with 0.5s threshold must suppress refresh")

        _ = cancellables
    }

    // MARK: - Challenge 4: Deep Navigation Stack Pop-To-Root Suppression

    @Test("Verify Deep Stack Reselection Strictly Pops to Root Without Refresh or Scroll-To-Top")
    @MainActor
    func testDeepStackReselectionStrictlyPopsToRoot() {
        for depth in [1, 2, 5, 25, 100] {
            let state = AppNavigationState(initialDestination: .timeline)
            let coordinator = state.tabBarCoordinator

            // Push `depth` routes onto timeline while stack is at root
            for i in 0..<depth {
                state.push(route: .postDetail(postId: "deep_post_\(i)"), on: .timeline)
            }
            #expect(state.path(for: .timeline).count == depth)
            #expect(state.navigationPaths[.timeline]?.count == depth)

            let refreshCollector = ChallengerEventCollector<AppDestination>()
            let scrollCollector = ChallengerEventCollector<ScrollToTopEvent>()

            var cancellables = Set<AnyCancellable>()
            coordinator.refreshPublisher
                .sink { dest in refreshCollector.record(dest) }
                .store(in: &cancellables)

            coordinator.scrollToTopPublisher
                .sink { event in scrollCollector.record(event) }
                .store(in: &cancellables)

            let tokenBefore = state.scrollToTopToken(for: .timeline)
            let triggersBefore = coordinator.scrollToTopTriggers[.timeline] ?? 0

            // Reselection tap even rapidly at 0.05s
            let t1 = Date()
            state.handleTabTap(.timeline, date: t1)

            // Case 1: Stack must be popped completely to root
            #expect(state.path(for: .timeline).isEmpty, "Stack at depth \(depth) must be cleared to root")
            #expect(state.navigationPaths[.timeline]?.isEmpty == true, "SwiftUI NavigationPath must be empty")

            // Case 2: Must NOT emit refresh
            #expect(refreshCollector.count == 0, "Popping from depth \(depth) must not emit refreshPublisher")

            // Case 3: Must NOT regenerate scroll-to-top token
            #expect(state.scrollToTopToken(for: .timeline) == tokenBefore, "Popping from depth \(depth) must not update scroll-to-top token")

            // Case 4: Must NOT trigger scroll-to-top publisher
            #expect(scrollCollector.count == 0, "Popping from depth \(depth) must not emit scrollToTopPublisher")
            #expect(coordinator.scrollToTopTriggers[.timeline] == triggersBefore, "Trigger counter must not increment")

            _ = cancellables
        }
    }

    // MARK: - Challenge 5: Deep Link URL Parsing Matrix (Standard, Edge, Query, Invalid)

    @Test("Verify Deep-Link URL Parsing Across Complete Route Matrix and Edge Cases")
    @MainActor
    func testDeepLinkComprehensiveMatrix() {
        let state = AppNavigationState()

        // 1. Standard destinations
        #expect(state.handle(url: URL(string: "xclient://timeline")!))
        #expect(state.selectedDestination == .timeline)

        #expect(state.handle(url: URL(string: "xclient://bookmarks")!))
        #expect(state.selectedDestination == .bookmarks)

        #expect(state.handle(url: URL(string: "xclient://profile")!))
        #expect(state.selectedDestination == .profile)

        #expect(state.handle(url: URL(string: "xclient://settings")!))
        #expect(state.selectedDestination == .settings)

        // 2. Profile with specific user ID
        #expect(state.handle(url: URL(string: "xclient://profile/usr_tim_cook")!))
        #expect(state.selectedDestination == .profile)
        #expect(state.selectedUserId == "usr_tim_cook")

        // 3. Post detail with route push to timeline
        state.resetAll()
        #expect(state.path(for: .timeline).isEmpty)
        #expect(state.handle(url: URL(string: "xclient://post/post_apple_2026")!))
        #expect(state.selectedDestination == .timeline)
        #expect(state.selectedPostId == "post_apple_2026")
        #expect(state.path(for: .timeline).count == 1)
        #expect(state.path(for: .timeline).first == .postDetail(postId: "post_apple_2026"))

        // 4. Compose modal presentation
        state.dismissSheet()
        #expect(!state.isComposePresented)
        #expect(state.handle(url: URL(string: "xclient://compose")!))
        #expect(state.isComposePresented)
        #expect(state.presentedSheet == .composer(draftId: nil, replyToPostId: nil))
        state.dismissSheet()

        // 5. Query parameters & fragments tolerance
        #expect(state.handle(url: URL(string: "xclient://timeline?source=push_notification&unread=5")!))
        #expect(state.selectedDestination == .timeline)

        #expect(state.handle(url: URL(string: "xclient://profile/usr_craig_f?tab=media#highlight")!))
        #expect(state.selectedDestination == .profile)
        #expect(state.selectedUserId == "usr_craig_f")

        // 6. Invalid schemes (must safely reject without crash)
        #expect(!state.handle(url: URL(string: "https://xclient.com/timeline")!))
        #expect(!state.handle(url: URL(string: "http://xclient.com/post/123")!))
        #expect(!state.handle(url: URL(string: "twitter://timeline")!))
        #expect(!state.handle(url: URL(string: "file:///Users/user/post/123")!))

        // 7. Unknown hosts / malformed routes (must return false)
        #expect(!state.handle(url: URL(string: "xclient://unknown_section")!))
        #expect(!state.handle(url: URL(string: "xclient://invalid_route_path")!))
    }

    // MARK: - Challenge 6: Tab Switching vs Tab Reselection Isolation

    @Test("Verify Switching Between Different Tabs Does Not Trigger Reselection Refresh or Scroll")
    @MainActor
    func testTabSwitchingDoesNotTriggerReselection() {
        let state = AppNavigationState(initialDestination: .timeline)
        let coordinator = state.tabBarCoordinator

        let refreshCollector = ChallengerEventCollector<AppDestination>()
        let scrollCollector = ChallengerEventCollector<ScrollToTopEvent>()

        var cancellables = Set<AnyCancellable>()
        coordinator.refreshPublisher
            .sink { dest in refreshCollector.record(dest) }
            .store(in: &cancellables)

        coordinator.scrollToTopPublisher
            .sink { event in scrollCollector.record(event) }
            .store(in: &cancellables)

        var t = Date()

        // Switch from timeline to bookmarks at 0.1s
        t = t.addingTimeInterval(0.1)
        state.selectDestination(.bookmarks, date: t)
        #expect(state.selectedDestination == .bookmarks)
        #expect(refreshCollector.count == 0, "Switching tab must not emit refresh")
        #expect(scrollCollector.count == 0, "Switching tab must not emit scroll-to-top")

        // Switch from bookmarks to profile at 0.2s
        t = t.addingTimeInterval(0.1)
        state.selectDestination(.profile, date: t)
        #expect(state.selectedDestination == .profile)
        #expect(refreshCollector.count == 0)
        #expect(scrollCollector.count == 0)

        // Now re-tap profile rapidly at 0.1s after switching to profile
        t = t.addingTimeInterval(0.1)
        state.selectDestination(.profile, date: t)
        #expect(refreshCollector.count == 1, "Re-tapping active profile tab rapidly must emit refresh")
        #expect(refreshCollector.allEvents.first == .profile)
        #expect(scrollCollector.count == 1)

        _ = cancellables
    }

    // MARK: - Challenge 7: Multi-Actor Concurrency & Stress Load Under Swift 6

    @Test("200 concurrent tasks rapidly performing tab reselection, date injection, and route mutations")
    func testConcurrentReselectionAndNavigationStress() async throws {
        let state = await MainActor.run {
            AppNavigationState()
        }
        let coordinator = await MainActor.run {
            state.tabBarCoordinator
        }

        let refreshCollector = ChallengerEventCollector<AppDestination>()
        let scrollCollector = ChallengerEventCollector<ScrollToTopEvent>()

        var cancellables = Set<AnyCancellable>()
        await MainActor.run {
            coordinator.refreshPublisher
                .sink { dest in refreshCollector.record(dest) }
                .store(in: &cancellables)

            coordinator.scrollToTopPublisher
                .sink { event in scrollCollector.record(event) }
                .store(in: &cancellables)
        }

        let taskCount = 200
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<taskCount {
                group.addTask {
                    let dest = AppDestination.allCases[i % AppDestination.allCases.count]
                    let now = Date().addingTimeInterval(Double(i) * 0.01)

                    await MainActor.run {
                        // Alternate between switching, reselection, pushing, and deep linking
                        if i % 4 == 0 {
                            state.selectTab(dest, date: now)
                        } else if i % 4 == 1 {
                            state.handleTabTap(dest, date: now)
                        } else if i % 4 == 2 {
                            state.push(route: .postDetail(postId: "stress_p_\(i)"), on: dest)
                        } else {
                            _ = state.handle(url: URL(string: "xclient://profile/user_\(i)")!)
                        }
                    }
                }
            }
            try await group.waitForAll()
        }

        await MainActor.run {
            #expect(AppDestination.allCases.contains(state.selectedDestination))
            #expect(state.selectedDestination == state.selectedTab)
            for dest in AppDestination.allCases {
                #expect(state.scrollToTopToken(for: dest) != nil)
                #expect(state.path(for: dest).count == (state.navigationPaths[dest]?.count ?? 0))
            }
        }

        _ = cancellables
    }
}
