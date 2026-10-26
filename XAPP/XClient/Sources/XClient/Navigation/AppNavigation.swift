//
//  AppNavigation.swift
//  XClient
//
//  Adaptive HIG Navigation Destinations, Route Typology, and Centralized Navigation State.
//  100% Swift 6 strict concurrency compliance.
//

import SwiftUI
import Combine

// MARK: - AppDestination

/// Destination tabs and primary navigation sections in XClient.
public enum AppDestination: String, Hashable, CaseIterable, Identifiable, Sendable {
    case timeline = "timeline"
    case bookmarks = "bookmarks"
    case profile = "profile"
    case settings = "settings"

    public var id: String { rawValue }

    /// Localized, human-readable title conforming to Apple HIG.
    public var title: String {
        switch self {
        case .timeline: return "Timeline"
        case .bookmarks: return "Bookmarks"
        case .profile: return "Profile"
        case .settings: return "Settings"
        }
    }

    /// Unselected outline SF Symbol icon name.
    public var iconName: String {
        switch self {
        case .timeline: return "house"
        case .bookmarks: return "bookmark"
        case .profile: return "person"
        case .settings: return "gearshape"
        }
    }

    /// Selected / filled SF Symbol icon name.
    public var selectedIconName: String {
        switch self {
        case .timeline: return "house.fill"
        case .bookmarks: return "bookmark.fill"
        case .profile: return "person.fill"
        case .settings: return "gearshape.fill"
        }
    }

    /// Alias for test compatibility.
    public var secondaryIconName: String {
        selectedIconName
    }

    /// Numeric index matching keyboard shortcuts (Cmd + 1..4).
    public var shortcutNumber: Int {
        switch self {
        case .timeline: return 1
        case .bookmarks: return 2
        case .profile: return 3
        case .settings: return 4
        }
    }

    /// SwiftUI KeyEquivalent for hardware keyboard navigation.
    public var keyEquivalent: KeyEquivalent {
        switch self {
        case .timeline: return "1"
        case .bookmarks: return "2"
        case .profile: return "3"
        case .settings: return "4"
        }
    }

    /// Keyboard shortcut character key for unit testing verification.
    public var keyboardShortcutKey: Character? {
        switch self {
        case .timeline: return "1"
        case .bookmarks: return "2"
        case .profile: return "3"
        case .settings: return "4"
        }
    }

    /// Accessibility description for VoiceOver assistive technologies.
    public var accessibilityLabel: String {
        switch self {
        case .timeline:
            return "Timeline tab, item \(shortcutNumber) of 4"
        case .bookmarks:
            return "Bookmarks tab, item \(shortcutNumber) of 4"
        case .profile:
            return "Profile tab, item \(shortcutNumber) of 4"
        case .settings:
            return "Settings tab, item \(shortcutNumber) of 4"
        }
    }
}

// MARK: - NavigationRoute

/// Strongly-typed route payload for stack navigation across tabs.
public enum NavigationRoute: Hashable, Sendable, Codable {
    case postDetail(postId: String)
    case userProfile(userId: String)
    case mediaLightbox(url: URL)
}

// MARK: - PresentedSheet

/// Modals and sheet presentation targets.
public enum PresentedSheet: Hashable, Sendable, Identifiable {
    case composer(draftId: String?, replyToPostId: String?)
    case settings
    case drafts

    public var id: String {
        switch self {
        case .composer(let draftId, let replyToPostId):
            return "composer_\(draftId ?? "none")_\(replyToPostId ?? "none")"
        case .settings:
            return "settings"
        case .drafts:
            return "drafts"
        }
    }
}

// MARK: - AppNavigationState

/// Centralized navigation state coordinator for XClient.
/// Fully isolated to @MainActor and conforming to Sendable for Swift 6 strict concurrency.
@MainActor
public final class AppNavigationState: ObservableObject, Sendable {
    // MARK: - Primary Selected Tab / Destination

    /// The currently selected primary destination.
    @Published public var selectedDestination: AppDestination {
        didSet {
            if selectedTab != selectedDestination {
                selectedTab = selectedDestination
            }
        }
    }

    /// Semantic alias for `selectedDestination` matching standard tab naming.
    @Published public var selectedTab: AppDestination {
        didSet {
            if selectedDestination != selectedTab {
                selectedDestination = selectedTab
            }
        }
    }

    // MARK: - Navigation Stacks

    /// Per-tab typed routes list for algorithmic unit testing.
    @Published public private(set) var tabPaths: [AppDestination: [NavigationRoute]]

    /// Independent per-tab SwiftUI NavigationPath for view hierarchy binding.
    @Published public var navigationPaths: [AppDestination: NavigationPath]

    // MARK: - Modal Presentation

    /// Currently active sheet presentation payload.
    @Published public var presentedSheet: PresentedSheet? {
        didSet {
            isComposePresented = (presentedSheet != nil && isComposerSheet(presentedSheet))
            isSettingsSheetPresented = (presentedSheet == .settings)
        }
    }

    /// Modal presentation flag for Compose sheet.
    @Published public var isComposePresented: Bool {
        didSet {
            if isComposePresented && presentedSheet == nil {
                presentedSheet = .composer(draftId: nil, replyToPostId: nil)
            } else if !isComposePresented && isComposerSheet(presentedSheet) {
                presentedSheet = nil
            }
        }
    }

    /// Modal presentation flag for Settings sheet.
    @Published public var isSettingsSheetPresented: Bool {
        didSet {
            if isSettingsSheetPresented && presentedSheet != .settings {
                presentedSheet = .settings
            } else if !isSettingsSheetPresented && presentedSheet == .settings {
                presentedSheet = nil
            }
        }
    }

    // MARK: - Regular Layout Selection States

    /// Multiplatform split-view column visibility (iPadOS / macOS).
    @Published public var columnVisibility: NavigationSplitViewVisibility

    /// Selected post ID for 2/3-column or detail presentation on regular layouts.
    @Published public var selectedPostId: String?

    /// Selected user ID for profile detail presentation.
    @Published public var selectedUserId: String?

    /// Badge counts per destination (e.g., unread timeline posts).
    @Published public var badgeCounts: [AppDestination: Int]

    /// Unique token regenerated whenever scroll-to-top is triggered for a destination.
    @Published public private(set) var scrollToTopTokens: [AppDestination: UUID]

    // MARK: - Sub-Coordinators & State
    public let tabBarCoordinator: TabBarCoordinator

    // MARK: - Initialization

    public init(
        initialDestination: AppDestination = .timeline,
        columnVisibility: NavigationSplitViewVisibility = .automatic
    ) {
        self.selectedDestination = initialDestination
        self.selectedTab = initialDestination
        self.tabPaths = [
            .timeline: [],
            .bookmarks: [],
            .profile: [],
            .settings: []
        ]
        self.navigationPaths = [
            .timeline: NavigationPath(),
            .bookmarks: NavigationPath(),
            .profile: NavigationPath(),
            .settings: NavigationPath()
        ]
        self.columnVisibility = columnVisibility
        self.presentedSheet = nil
        self.isComposePresented = false
        self.isSettingsSheetPresented = false
        self.selectedPostId = nil
        self.selectedUserId = nil
        self.badgeCounts = [
            .timeline: 0,
            .bookmarks: 0,
            .profile: 0,
            .settings: 0
        ]
        self.scrollToTopTokens = [
            .timeline: UUID(),
            .bookmarks: UUID(),
            .profile: UUID(),
            .settings: UUID()
        ]
        self.tabBarCoordinator = TabBarCoordinator()

        // Attach coordinator
        self.tabBarCoordinator.attach(to: self)
    }

    private func isComposerSheet(_ sheet: PresentedSheet?) -> Bool {
        guard let sheet = sheet else { return false }
        switch sheet {
        case .composer: return true
        default: return false
        }
    }

    // MARK: - Tab Switching

    /// Switches the active destination tab, handling re-selection behavior if already active with optional date injection.
    public func selectDestination(_ destination: AppDestination, date: Date = Date()) {
        if selectedDestination == destination {
            tabBarCoordinator.handleTabReselection(destination, date: date)
        } else {
            selectedDestination = destination
            tabBarCoordinator.handleTabSelection(destination, date: date)
        }
    }

    /// Selects active tab directly.
    public func selectTab(_ destination: AppDestination, date: Date = Date()) {
        selectDestination(destination, date: date)
    }

    // MARK: - Navigation Path Management

    /// Returns a SwiftUI two-way Binding for the navigation path associated with the given destination.
    public func bindingForPath(of destination: AppDestination) -> Binding<NavigationPath> {
        Binding(
            get: { self.navigationPaths[destination] ?? NavigationPath() },
            set: { self.navigationPaths[destination] = $0 }
        )
    }

    /// Returns the typed route list for the specified destination.
    public func path(for destination: AppDestination) -> [NavigationRoute] {
        tabPaths[destination] ?? []
    }

    /// Returns the typed route list for the currently selected destination.
    public var currentPath: [NavigationRoute] {
        tabPaths[selectedDestination] ?? []
    }

    /// Pushes a typed NavigationRoute onto the active or specified destination's navigation stack.
    public func push(route: NavigationRoute, on destination: AppDestination? = nil) {
        let dest = destination ?? selectedDestination
        var routes = tabPaths[dest] ?? []
        routes.append(route)
        tabPaths[dest] = routes

        var path = navigationPaths[dest] ?? NavigationPath()
        path.append(route)
        navigationPaths[dest] = path
    }

    /// Generic push for any Hashable item.
    public func push<T: Hashable>(_ item: T, on destination: AppDestination? = nil) {
        let dest = destination ?? selectedDestination
        var path = navigationPaths[dest] ?? NavigationPath()
        path.append(item)
        navigationPaths[dest] = path

        if let route = item as? NavigationRoute {
            var routes = tabPaths[dest] ?? []
            routes.append(route)
            tabPaths[dest] = routes
        }
    }

    /// Pops the top item from the active or specified destination's navigation stack.
    @discardableResult
    public func pop(on destination: AppDestination? = nil) -> NavigationRoute? {
        let dest = destination ?? selectedDestination
        var routes = tabPaths[dest] ?? []
        guard !routes.isEmpty else { return nil }
        let popped = routes.removeLast()
        tabPaths[dest] = routes

        if var path = navigationPaths[dest], !path.isEmpty {
            path.removeLast()
            navigationPaths[dest] = path
        }

        return popped
    }

    /// Resets the navigation path to root for the specified destination.
    public func popToRoot(on destination: AppDestination? = nil) {
        let dest = destination ?? selectedDestination
        tabPaths[dest] = []
        navigationPaths[dest] = NavigationPath()
    }

    /// Resets all navigation paths across all destinations.
    public func resetAllPaths() {
        for destination in AppDestination.allCases {
            tabPaths[destination] = []
            navigationPaths[destination] = NavigationPath()
        }
        selectedPostId = nil
        selectedUserId = nil
    }

    /// Resets the full navigation state back to initial default.
    public func resetAll() {
        resetAllPaths()
        selectedDestination = .timeline
        dismissSheet()
    }

    // MARK: - Modals / Sheets Presentation

    /// Presents a modal sheet.
    public func presentSheet(_ sheet: PresentedSheet) {
        presentedSheet = sheet
    }

    /// Dismisses the currently presented sheet.
    public func dismissSheet() {
        presentedSheet = nil
        isComposePresented = false
        isSettingsSheetPresented = false
    }

    // MARK: - Gestures & Tap Handlers

    /// Handles a tab tap event, delegating re-selection or tab switching with date injection.
    public func handleTabTap(_ destination: AppDestination, date: Date = Date()) {
        if selectedDestination == destination {
            tabBarCoordinator.handleTabReselection(destination, date: date)
        } else {
            selectDestination(destination, date: date)
        }
    }

    /// Returns the scroll-to-top token for a given destination.
    public func scrollToTopToken(for destination: AppDestination) -> UUID? {
        scrollToTopTokens[destination]
    }

    /// Regenerates scroll-to-top token for a given destination.
    internal func updateScrollToTopToken(for destination: AppDestination) {
        scrollToTopTokens[destination] = UUID()
    }

    // MARK: - Badge Management

    /// Returns the badge count for the given destination (0 = no badge).
    public func badgeCount(for destination: AppDestination) -> Int {
        badgeCounts[destination] ?? 0
    }

    /// Sets the badge count for the given destination.
    public func setBadgeCount(_ count: Int, for destination: AppDestination) {
        badgeCounts[destination] = max(0, count)
    }

    /// Increments the badge count for the given destination.
    public func incrementBadge(for destination: AppDestination, by amount: Int = 1) {
        let current = badgeCounts[destination] ?? 0
        badgeCounts[destination] = max(0, current + amount)
    }

    /// Clears the badge count for the given destination.
    public func clearBadge(for destination: AppDestination) {
        badgeCounts[destination] = 0
    }

    // MARK: - Deep Linking & URL Handling

    /// Handles incoming deep-link URL schemes (e.g., `xclient://timeline`, `xclient://compose`).
    @discardableResult
    public func handle(url: URL) -> Bool {
        guard url.scheme == "xclient" else { return false }

        let host = url.host ?? url.pathComponents.first(where: { $0 != "/" })
        switch host {
        case "timeline":
            selectDestination(.timeline)
            return true
        case "bookmarks":
            selectDestination(.bookmarks)
            return true
        case "profile":
            selectDestination(.profile)
            if let userParam = url.pathComponents.dropFirst().first {
                selectedUserId = userParam
            }
            return true
        case "settings":
            selectDestination(.settings)
            return true
        case "post":
            if let postId = url.pathComponents.dropFirst().first {
                selectedPostId = postId
                selectDestination(.timeline)
                push(route: .postDetail(postId: postId))
            }
            return true
        case "compose":
            presentSheet(.composer(draftId: nil, replyToPostId: nil))
            return true
        default:
            return false
        }
    }
}
