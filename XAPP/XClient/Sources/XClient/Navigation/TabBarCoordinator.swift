//
//  TabBarCoordinator.swift
//  XClient
//
//  Coordinates tab re-selection gestures, double-tap scroll-to-top triggers,
//  feed refresh events, and unread badge formatting.
//  100% Swift 6 strict concurrency compliance.
//

import SwiftUI
import Combine

// MARK: - ScrollToTopEvent

/// Event payload carrying scroll-to-top and refresh instructions.
public struct ScrollToTopEvent: Sendable, Equatable {
    public let destination: AppDestination
    public let timestamp: Date
    public let isDoubleTap: Bool

    public init(destination: AppDestination, timestamp: Date = Date(), isDoubleTap: Bool = false) {
        self.destination = destination
        self.timestamp = timestamp
        self.isDoubleTap = isDoubleTap
    }
}

// MARK: - TabBarCoordinator

/// Coordinates tab bar interactions, re-selection actions, double-tap gestures, and badge presentation.
/// Fully isolated to @MainActor and conforming to Sendable for Swift 6 strict concurrency.
@MainActor
public final class TabBarCoordinator: ObservableObject, Sendable {
    // MARK: - Navigation State Link
    private weak var navigationState: AppNavigationState?

    // MARK: - Published State

    /// Incremental trigger counters for SwiftUI `.onChange(of: scrollToTopTriggers[destination])` observers.
    @Published public private(set) var scrollToTopTriggers: [AppDestination: Int] = [
        .timeline: 0,
        .bookmarks: 0,
        .profile: 0,
        .settings: 0
    ]

    /// Latest scroll-to-top event payload.
    @Published public private(set) var lastScrollToTopEvent: ScrollToTopEvent?

    /// Double-tap threshold in seconds (standard iOS HIG: 0.35s).
    public var doubleTapThreshold: TimeInterval = 0.35

    // MARK: - Internal Timestamps
    private var lastTapTimes: [AppDestination: Date] = [:]

    // MARK: - Combine Publishers
    public let scrollToTopPublisher = PassthroughSubject<ScrollToTopEvent, Never>()
    public let refreshPublisher = PassthroughSubject<AppDestination, Never>()

    // MARK: - Initialization

    public init() {}

    internal func attach(to state: AppNavigationState) {
        self.navigationState = state
    }

    // MARK: - Interaction Handlers

    /// Handles initial selection of a different destination tab.
    public func handleTabSelection(_ destination: AppDestination, date: Date = Date()) {
        lastTapTimes[destination] = date
    }

    /// Handles re-selection of the currently active destination tab with date injection.
    ///
    /// Apple HIG Compliance:
    /// - Deep Stack: Pops navigation stack back to root without triggering scroll-to-top or refresh.
    /// - Root Stack (Single / Slow tap > 0.35s): Always triggers scroll-to-top (isDoubleTap = false). Does not refresh feed.
    /// - Root Stack (Rapid double-tap < 0.35s): Triggers scroll-to-top (isDoubleTap = true) AND triggers feed refresh.
    public func handleTabReselection(_ destination: AppDestination, date: Date = Date()) {
        guard let state = navigationState else { return }

        let previousTap = lastTapTimes[destination] ?? .distantPast
        let timeInterval = date.timeIntervalSince(previousTap)
        let isDoubleTap = (timeInterval <= doubleTapThreshold)

        lastTapTimes[destination] = date

        let path = state.tabPaths[destination] ?? []
        if !path.isEmpty {
            // Case 1: Deep in navigation stack -> Pop back to root
            state.popToRoot(on: destination)
        } else {
            // Case 2: Already at root -> Always trigger scroll-to-top
            triggerScrollToTop(for: destination, isDoubleTap: isDoubleTap, timestamp: date)

            // Case 3: Rapid double-tap -> Also trigger feed refresh
            if isDoubleTap {
                triggerRefresh(for: destination)
            }
        }
    }

    /// Triggers a scroll-to-top event for the given destination.
    public func triggerScrollToTop(for destination: AppDestination, isDoubleTap: Bool = false, timestamp: Date = Date()) {
        let event = ScrollToTopEvent(destination: destination, timestamp: timestamp, isDoubleTap: isDoubleTap)
        lastScrollToTopEvent = event
        scrollToTopTriggers[destination] = (scrollToTopTriggers[destination] ?? 0) + 1
        navigationState?.updateScrollToTopToken(for: destination)
        scrollToTopPublisher.send(event)
    }

    /// Triggers a refresh request for the given destination.
    public func triggerRefresh(for destination: AppDestination) {
        refreshPublisher.send(destination)
    }

    // MARK: - Badge Formatting Helpers

    /// Formats an integer count into a clean HIG badge label (e.g. 0 -> nil, 5 -> "5", 140 -> "99+").
    public static func formattedBadgeString(for count: Int) -> String? {
        guard count > 0 else { return nil }
        if count > 99 {
            return "99+"
        } else {
            return "\(count)"
        }
    }
}
