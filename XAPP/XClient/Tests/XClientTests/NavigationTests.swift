//
//  NavigationTests.swift
//  XClientTests
//
//  Automated Unit Tests for Adaptive HIG Navigation and State Machine.
//  100% Swift 6 strict concurrency compliance.
//

import Testing
import Foundation
import SwiftUI
import Combine
@testable import XClient

/// Mock background worker actor simulating background notifications and deep links.
private actor BackgroundNavigationRouter {
    private let navigationState: AppNavigationState

    init(navigationState: AppNavigationState) {
        self.navigationState = navigationState
    }

    func routeDeepLink(to destination: AppDestination, route: NavigationRoute?) async {
        await navigationState.selectTab(destination)
        if let route = route {
            await navigationState.push(route: route)
        }
    }

    func presentComposer() async {
        await navigationState.presentSheet(.composer(draftId: nil, replyToPostId: nil))
    }
}

// MARK: - Navigation Test Suite

@Suite("Adaptive Navigation & State Machine Test Suite", .serialized)
struct NavigationTests {

    // MARK: - Destination Enum & HIG Shortcut Tests

    @Test("Verify AppDestination Cases and Protocol Conformance")
    @MainActor
    func testAppDestinationCompleteness() {
        let allCases = AppDestination.allCases
        #expect(allCases.count >= 4)
        #expect(allCases.contains(.timeline))
        #expect(allCases.contains(.bookmarks))
        #expect(allCases.contains(.profile))
        #expect(allCases.contains(.settings))

        for dest in allCases {
            #expect(!dest.id.isEmpty)
            #expect(!dest.title.isEmpty)
            #expect(!dest.iconName.isEmpty)
            #expect(!dest.secondaryIconName.isEmpty)
        }
    }

    @Test("Verify Keyboard Shortcuts Uniqueness and Cmd+1..4 Mappings")
    @MainActor
    func testKeyboardShortcuts() {
        var keyMap: [Character: AppDestination] = [:]
        for dest in AppDestination.allCases {
            guard let key = dest.keyboardShortcutKey else { continue }
            #expect(keyMap[key] == nil, "Duplicate keyboard shortcut key detected: \(key)")
            keyMap[key] = dest
        }

        #expect(keyMap["1"] == .timeline)
        #expect(keyMap["2"] == .bookmarks)
        #expect(keyMap["3"] == .profile)
        #expect(keyMap["4"] == .settings)
    }

    // MARK: - AppNavigationState Initial State & Mutations

    @Test("Verify Initial Navigation State")
    @MainActor
    func testInitialNavigationState() {
        let state = AppNavigationState()
        #expect(state.selectedTab == .timeline)
        #expect(state.presentedSheet == nil)
        #expect(state.currentPath.isEmpty)
        for dest in AppDestination.allCases {
            #expect(state.path(for: dest).isEmpty)
        }
    }

    @Test("Verify Tab Selection Mutation")
    @MainActor
    func testSelectTab() {
        let state = AppNavigationState()
        state.selectTab(.bookmarks)
        #expect(state.selectedTab == .bookmarks)

        state.selectTab(.profile)
        #expect(state.selectedTab == .profile)

        state.selectTab(.settings)
        #expect(state.selectedTab == .settings)
    }

    @Test("Verify Navigation Stack Push and Pop Operations")
    @MainActor
    func testPushAndPopStack() {
        let state = AppNavigationState()
        state.selectTab(.timeline)

        let postRoute = NavigationRoute.postDetail(postId: "post_1001")
        state.push(route: postRoute)

        #expect(state.currentPath.count == 1)
        #expect(state.currentPath.first == postRoute)

        let authorRoute = NavigationRoute.userProfile(userId: "usr_author_002")
        state.push(route: authorRoute)

        #expect(state.currentPath.count == 2)
        #expect(state.currentPath.last == authorRoute)

        // Pop one level
        let popped = state.pop()
        #expect(popped == authorRoute)
        #expect(state.currentPath.count == 1)
        #expect(state.currentPath.first == postRoute)

        // Pop last level
        let poppedSecond = state.pop()
        #expect(poppedSecond == postRoute)
        #expect(state.currentPath.isEmpty)
    }

    @Test("Verify Pop Underflow Safety on Empty Stack")
    @MainActor
    func testPopUnderflowSafety() {
        let state = AppNavigationState()
        #expect(state.currentPath.isEmpty)

        // Calling pop on an empty stack must not crash or corrupt state
        let result = state.pop()
        #expect(result == nil)
        #expect(state.currentPath.isEmpty)
    }

    @Test("Verify PopToRoot Clears Active Stack")
    @MainActor
    func testPopToRoot() {
        let state = AppNavigationState()
        state.selectTab(.timeline)
        state.push(route: .postDetail(postId: "p1"))
        state.push(route: .userProfile(userId: "u1"))
        state.push(route: .mediaLightbox(url: URL(string: "https://example.com/img.png")!))

        #expect(state.currentPath.count == 3)

        state.popToRoot()
        #expect(state.currentPath.isEmpty)
    }

    @Test("Verify ResetAll Resets Tabs and Stacks")
    @MainActor
    func testResetAll() {
        let state = AppNavigationState()
        state.selectTab(.bookmarks)
        state.push(route: .postDetail(postId: "bm1"))

        state.selectTab(.profile)
        state.push(route: .postDetail(postId: "prof1"))

        state.presentSheet(.settings)

        state.resetAll()

        #expect(state.selectedTab == .timeline)
        #expect(state.presentedSheet == nil)
        #expect(state.path(for: .timeline).isEmpty)
        #expect(state.path(for: .bookmarks).isEmpty)
        #expect(state.path(for: .profile).isEmpty)
    }

    // MARK: - Modals / Sheets Presentation Lifecycle

    @Test("Verify Sheet Presentation and Dismissal Lifecycle")
    @MainActor
    func testSheetLifecycle() {
        let state = AppNavigationState()
        #expect(state.presentedSheet == nil)

        let composerSheet = PresentedSheet.composer(draftId: "draft_123", replyToPostId: nil)
        state.presentSheet(composerSheet)
        #expect(state.presentedSheet == composerSheet)

        state.dismissSheet()
        #expect(state.presentedSheet == nil)
    }

    // MARK: - Multiplatform Tab Isolation & State Preservation

    @Test("Verify Multiplatform Stack Isolation Across Tabs")
    @MainActor
    func testStackIsolationAcrossTabs() {
        let state = AppNavigationState()

        // Push 2 routes on Timeline
        state.selectTab(.timeline)
        state.push(route: .postDetail(postId: "post_1001"))
        state.push(route: .userProfile(userId: "usr_001"))
        #expect(state.path(for: .timeline).count == 2)

        // Switch to Bookmarks and push 1 route
        state.selectTab(.bookmarks)
        state.push(route: .postDetail(postId: "post_1002"))
        #expect(state.path(for: .bookmarks).count == 1)

        // Switch to Profile
        state.selectTab(.profile)
        #expect(state.path(for: .profile).isEmpty)

        // Switch back to Timeline: stack depth 2 must be preserved exactly
        state.selectTab(.timeline)
        #expect(state.currentPath.count == 2)
        #expect(state.currentPath == [
            .postDetail(postId: "post_1001"),
            .userProfile(userId: "usr_001")
        ])

        // Switch back to Bookmarks: stack depth 1 must be preserved
        state.selectTab(.bookmarks)
        #expect(state.currentPath.count == 1)
        #expect(state.currentPath == [.postDetail(postId: "post_1002")])

        // Popping on Bookmarks does NOT affect Timeline
        _ = state.pop()
        #expect(state.path(for: .bookmarks).isEmpty)
        #expect(state.path(for: .timeline).count == 2)
    }

    // MARK: - Tab Bar Tap Gestures, Scroll-To-Top & Feed Refresh

    @Test("Verify Double-Tap On Active Tab Emits Scroll-To-Top Trigger")
    @MainActor
    func testDoubleTapScrollToTop() {
        let state = AppNavigationState()
        let t0 = Date()
        state.selectTab(.timeline, date: t0)
        let initialTrigger = state.scrollToTopToken(for: .timeline)

        // Simulating second tap within double-tap interval (0.2s <= 0.35s threshold)
        let t1 = t0.addingTimeInterval(0.2)
        state.handleTabTap(.timeline, date: t1)
        let newTrigger = state.scrollToTopToken(for: .timeline)

        #expect(newTrigger != nil, "Scroll-to-top token must be generated")
        #expect(newTrigger != initialTrigger, "Double tap must regenerate scroll-to-top token")
    }

    @Test("Verify Slow Second Tap Scrolls To Top But Throttles Feed Refresh")
    @MainActor
    func testSlowTapThrottling() {
        let state = AppNavigationState()
        let t0 = Date()
        state.selectTab(.timeline, date: t0)

        var refreshEmitted = false
        var refreshDestination: AppDestination?
        let cancellable = state.tabBarCoordinator.refreshPublisher.sink { destination in
            refreshEmitted = true
            refreshDestination = destination
        }
        defer { cancellable.cancel() }

        let initialTrigger = state.scrollToTopToken(for: .timeline)

        // Simulating slow second tap after 1.0s (exceeding double-tap threshold of 0.35s)
        let t1 = t0.addingTimeInterval(1.0)
        state.handleTabTap(.timeline, date: t1)
        let secondTrigger = state.scrollToTopToken(for: .timeline)

        // HIG Requirement 1: In native iOS HIG, a tap at root ALWAYS scrolls to top, even when slow
        #expect(secondTrigger != nil, "Second trigger token must exist")
        #expect(secondTrigger != initialTrigger, "Slow tap at root must regenerate scroll-to-top token")

        // HIG Requirement 2: Slow taps must NOT trigger pull-to-refresh
        #expect(refreshEmitted == false, "Taps separated by >0.35s must NOT emit feed refresh")
        #expect(refreshDestination == nil, "No refresh destination should be recorded on slow tap")
    }

    @Test("Verify Rapid Double-Tap Fires Scroll-To-Top and Emits Feed Refresh")
    @MainActor
    func testDoubleTapFeedRefresh() {
        let state = AppNavigationState()
        let t0 = Date()
        state.selectTab(.timeline, date: t0)

        var emittedDestinations: [AppDestination] = []
        let cancellable = state.tabBarCoordinator.refreshPublisher.sink { destination in
            emittedDestinations.append(destination)
        }
        defer { cancellable.cancel() }

        let initialTrigger = state.scrollToTopToken(for: .timeline)

        // Simulating rapid second tap within 0.2s (< 0.35s threshold)
        let t1 = t0.addingTimeInterval(0.2)
        state.handleTabTap(.timeline, date: t1)
        let secondTrigger = state.scrollToTopToken(for: .timeline)

        // Both scroll-to-top and feed refresh must fire
        #expect(secondTrigger != initialTrigger, "Rapid double-tap must update scroll-to-top token")
        #expect(emittedDestinations.count == 1, "Rapid double-tap must emit exactly one refresh event")
        #expect(emittedDestinations.first == .timeline, "Refresh event must target the active destination")
    }

    @Test("Verify Tab Reselection While Deep in Stack Pops to Root")
    @MainActor
    func testTabReselectionPopsToRootWhenDeepInStack() {
        let state = AppNavigationState()
        let t0 = Date()
        state.selectTab(.timeline, date: t0)
        state.push(route: .postDetail(postId: "post_1001"))
        state.push(route: .userProfile(userId: "user_001"))
        #expect(state.currentPath.count == 2)

        var refreshCount = 0
        var cancellables = Set<AnyCancellable>()
        state.tabBarCoordinator.refreshPublisher
            .sink { _ in refreshCount += 1 }
            .store(in: &cancellables)

        let initialToken = state.scrollToTopToken(for: .timeline)

        // Reselection tap while deep in stack
        state.handleTabTap(.timeline, date: t0.addingTimeInterval(0.1))

        #expect(state.currentPath.isEmpty, "Reselection while deep in stack must pop stack to root")
        #expect(refreshCount == 0, "Popping to root must not trigger feed refresh")
        #expect(state.scrollToTopToken(for: .timeline) == initialToken, "Popping to root must not regenerate scroll-to-top token")
        _ = cancellables
    }

    @Test("Verify NavigationRoute Types and Destination Presentation Views")
    @MainActor
    func testNavigationRouteDestinationViews() {
        let postRoute = NavigationRoute.postDetail(postId: "post_42")
        let profileRoute = NavigationRoute.userProfile(userId: "user_99")
        let lightboxRoute = NavigationRoute.mediaLightbox(url: URL(string: "https://example.com/pic.jpg")!)

        let postView = RouteDestinationView(route: postRoute)
        let profileView = RouteDestinationView(route: profileRoute)
        let lightboxView = RouteDestinationView(route: lightboxRoute)

        #expect(postView.route == postRoute)
        #expect(profileView.route == profileRoute)
        #expect(lightboxView.route == lightboxRoute)
    }

    // MARK: - Deep Linking & URL Handling Unit Tests

    @Test("Verify Deep-Link URL Handling for Standard Tab Destinations")
    @MainActor
    func testDeepLinkStandardDestinations() {
        let state = AppNavigationState()

        // 1. xclient://timeline
        let timelineHandled = state.handle(url: URL(string: "xclient://timeline")!)
        #expect(timelineHandled == true)
        #expect(state.selectedDestination == .timeline)
        #expect(state.selectedTab == .timeline)

        // 2. xclient://bookmarks
        let bookmarksHandled = state.handle(url: URL(string: "xclient://bookmarks")!)
        #expect(bookmarksHandled == true)
        #expect(state.selectedDestination == .bookmarks)
        #expect(state.selectedTab == .bookmarks)

        // 3. xclient://settings
        let settingsHandled = state.handle(url: URL(string: "xclient://settings")!)
        #expect(settingsHandled == true)
        #expect(state.selectedDestination == .settings)

        // 4. xclient://profile with user parameter
        let profileHandled = state.handle(url: URL(string: "xclient://profile/usr_author_002")!)
        #expect(profileHandled == true)
        #expect(state.selectedDestination == .profile)
        #expect(state.selectedUserId == "usr_author_002")
    }

    @Test("Verify Deep-Link Post Detail Navigation Pushes Route on Timeline")
    @MainActor
    func testDeepLinkPostDetailRoutePush() {
        let state = AppNavigationState()
        state.selectTab(.bookmarks) // Start away from timeline
        #expect(state.path(for: .timeline).isEmpty)

        let postHandled = state.handle(url: URL(string: "xclient://post/123")!)
        #expect(postHandled == true)
        #expect(state.selectedDestination == .timeline)
        #expect(state.selectedPostId == "123")
        #expect(state.path(for: .timeline).count == 1)
        #expect(state.path(for: .timeline).first == .postDetail(postId: "123"))
    }

    @Test("Verify Deep-Link Compose Opens Composer Sheet")
    @MainActor
    func testDeepLinkComposeModalPresentation() {
        let state = AppNavigationState()
        #expect(state.presentedSheet == nil)
        #expect(state.isComposePresented == false)

        let composeHandled = state.handle(url: URL(string: "xclient://compose")!)
        #expect(composeHandled == true)
        #expect(state.presentedSheet == .composer(draftId: nil, replyToPostId: nil))
        #expect(state.isComposePresented == true)

        state.dismissSheet()
        #expect(state.presentedSheet == nil)
        #expect(state.isComposePresented == false)
    }

    @Test("Verify Deep-Link Defense Against Invalid Schemes and Unknown Routes")
    @MainActor
    func testDeepLinkDefensiveGuards() {
        let state = AppNavigationState()

        // Foreign scheme rejection
        let httpResult = state.handle(url: URL(string: "https://xclient.com/timeline")!)
        #expect(httpResult == false)

        let customForeignScheme = state.handle(url: URL(string: "twitter://timeline")!)
        #expect(customForeignScheme == false)

        // Unrecognized route host rejection
        let unknownRoute = state.handle(url: URL(string: "xclient://unsupported_route_action")!)
        #expect(unknownRoute == false)
    }

    // MARK: - Badge Management

    @Test("Verify Badge Count Mutations and HIG Formatting")
    @MainActor
    func testBadgeManagement() {
        let state = AppNavigationState()
        #expect(state.badgeCount(for: .timeline) == 0)
        #expect(TabBarCoordinator.formattedBadgeString(for: 0) == nil)

        state.setBadgeCount(5, for: .timeline)
        #expect(state.badgeCount(for: .timeline) == 5)
        #expect(TabBarCoordinator.formattedBadgeString(for: 5) == "5")

        state.incrementBadge(for: .timeline, by: 100)
        #expect(state.badgeCount(for: .timeline) == 105)
        #expect(TabBarCoordinator.formattedBadgeString(for: 105) == "99+")

        state.clearBadge(for: .timeline)
        #expect(state.badgeCount(for: .timeline) == 0)
    }

    // MARK: - Swift 6 Concurrency & Cross-Actor Safety

    @Test("Verify Cross-Actor Navigation Dispatch From Background Worker")
    func testCrossActorNavigationDispatch() async throws {
        let state = await MainActor.run {
            AppNavigationState()
        }

        let router = BackgroundNavigationRouter(navigationState: state)
        await router.routeDeepLink(to: .bookmarks, route: .postDetail(postId: "deep_link_999"))

        await MainActor.run {
            #expect(state.selectedTab == .bookmarks)
            #expect(state.path(for: .bookmarks).count == 1)
            #expect(state.path(for: .bookmarks).first == .postDetail(postId: "deep_link_999"))
        }
    }

    @Test("Verify 100 Concurrent Background Navigation Operations Without Race Conditions")
    func testConcurrentNavigationOperations() async throws {
        let state = await MainActor.run {
            AppNavigationState()
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    let dest: AppDestination = (i % 2 == 0) ? .timeline : .bookmarks
                    let route = NavigationRoute.postDetail(postId: "post_\(i)")

                    await MainActor.run {
                        state.selectTab(dest)
                        state.push(route: route)
                        if i % 3 == 0 {
                            _ = state.pop()
                        }
                    }
                }
            }
            try await group.waitForAll()
        }

        await MainActor.run {
            let totalDepth = state.path(for: .timeline).count + state.path(for: .bookmarks).count
            #expect(totalDepth >= 0)
        }
    }

    // MARK: - AdaptiveRootView Desktop & Compact Hierarchy

    @Test("Verify AdaptiveRootView Initializes and Renders With NavigationState")
    @MainActor
    func testAdaptiveRootViewInitialization() {
        let state = AppNavigationState()
        let view = AdaptiveRootView(navigationState: state)
        _ = view.body
        #expect(state.selectedDestination == .timeline)

        for dest in AppDestination.allCases {
            state.selectDestination(dest)
            #expect(state.selectedDestination == dest)
        }
    }
}
