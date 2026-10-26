//
//  AdaptiveRootView.swift
//  XClient
//
//  Multiplatform Root Navigation Shell. Dynamically adapts between:
//  - Compact Layout: Native iOS bottom TabView with unread badges & floating Compose FAB.
//  - Regular Layout: iPad & macOS NavigationSplitView with collapsible Sidebar & Cmd+1..4 shortcuts.
//  100% Swift 6 strict concurrency compliance.
//

import SwiftUI
import XKitModels

// MARK: - AdaptiveRootView

/// Root responsive navigation container for XClient.
public struct AdaptiveRootView: View {
    @StateObject private var navigationState: AppNavigationState
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    public init(navigationState: AppNavigationState = AppNavigationState()) {
        _navigationState = StateObject(wrappedValue: navigationState)
    }

    public var body: some View {
        Group {
            #if os(macOS)
            // macOS always uses desktop Sidebar NavigationSplitView
            RegularRootView()
            #else
            // iOS dynamically adapts based on window size class (iPhone vs iPad vs Slide Over)
            if horizontalSizeClass == .compact {
                CompactRootView()
            } else {
                RegularRootView()
            }
            #endif
        }
        .environmentObject(navigationState)
        .environmentObject(navigationState.tabBarCoordinator)
        .sheet(isPresented: $navigationState.isComposePresented) {
            ComposeModalHost()
                .environmentObject(navigationState)
        }
        .background {
            // Global keyboard shortcuts (Cmd+1..4, Cmd+N, Cmd+R)
            KeyboardShortcutsHandler(state: navigationState)
        }
    }
}

// MARK: - Compact Layout (iPhone / Slide Over)

/// Compact bottom TabBar layout optimized for one-handed thumb reachability on iPhone.
public struct CompactRootView: View {
    @EnvironmentObject private var navigationState: AppNavigationState
    @EnvironmentObject private var coordinator: TabBarCoordinator

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: Binding(
                get: { navigationState.selectedDestination },
                set: { navigationState.selectDestination($0) }
            )) {
                ForEach(AppDestination.allCases) { destination in
                    NavigationStack(path: navigationState.bindingForPath(of: destination)) {
                        DestinationContentHost(destination: destination)
                    }
                    .tabItem {
                        Label(
                            destination.title,
                            systemImage: navigationState.selectedDestination == destination
                                ? destination.selectedIconName
                                : destination.iconName
                        )
                    }
                    .tag(destination)
                    .badge(TabBarCoordinator.formattedBadgeString(for: navigationState.badgeCount(for: destination)))
                }
            }

            // Floating Compose Button positioned above TabBar
            FloatingComposeButton()
                .padding(.trailing, 16)
                .padding(.bottom, 60)
        }
    }
}

// MARK: - Regular Layout (iPad / macOS)

/// Regular multi-column NavigationSplitView layout with collapsible sidebar and keyboard shortcuts.
public struct RegularRootView: View {
    @EnvironmentObject private var navigationState: AppNavigationState
    @EnvironmentObject private var coordinator: TabBarCoordinator

    public init() {}

    public var body: some View {
        NavigationSplitView(columnVisibility: $navigationState.columnVisibility) {
            SidebarView()
                .navigationTitle("XClient")
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
                #else
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
                #endif
        } detail: {
            NavigationStack(path: navigationState.bindingForPath(of: navigationState.selectedDestination)) {
                DestinationContentHost(destination: navigationState.selectedDestination)
            }
        }
        #if os(macOS)
        .navigationSplitViewStyle(.balanced)
        #endif
    }
}

// MARK: - Sidebar View

/// Desktop / tablet sidebar with destination list, unread badge pills, and compose button.
public struct SidebarView: View {
    @EnvironmentObject private var navigationState: AppNavigationState
    @EnvironmentObject private var coordinator: TabBarCoordinator

    public init() {}

    public var body: some View {
        List(selection: Binding(
            get: { navigationState.selectedDestination },
            set: { if let dest = $0 { navigationState.selectDestination(dest) } }
        )) {
            Section {
                ForEach(AppDestination.allCases) { destination in
                    SidebarRow(destination: destination)
                        .tag(destination)
                }
            } header: {
                Text("Feeds & Library")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            SidebarBottomBar()
        }
    }
}

// MARK: - Sidebar Row

public struct SidebarRow: View {
    let destination: AppDestination
    @EnvironmentObject private var navigationState: AppNavigationState

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: navigationState.selectedDestination == destination
                ? destination.selectedIconName
                : destination.iconName)
                .frame(width: 22, height: 22)
                .foregroundStyle(navigationState.selectedDestination == destination ? Color.accentColor : .primary)

            Text(destination.title)
                .font(.body)
                .fontWeight(navigationState.selectedDestination == destination ? .semibold : .regular)

            Spacer()

            let badgeCount = navigationState.badgeCount(for: destination)
            if let badgeText = TabBarCoordinator.formattedBadgeString(for: badgeCount) {
                Text(badgeText)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
            }

            // Keyboard shortcut hint on macOS
            #if os(macOS)
            Text("⌘\(destination.shortcutNumber)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            #endif
        }
        .padding(.vertical, 4)
        .accessibilityLabel(destination.accessibilityLabel)
    }
}

// MARK: - Sidebar Bottom Bar

public struct SidebarBottomBar: View {
    @EnvironmentObject private var navigationState: AppNavigationState

    public var body: some View {
        VStack(spacing: 8) {
            Divider()

            Button(action: {
                navigationState.isComposePresented = true
            }) {
                HStack {
                    Image(systemName: "square.and.pencil")
                    Text("New Post")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        #if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        #else
        .background(Color(uiColor: .systemBackground))
        #endif
    }
}

// MARK: - Floating Compose Button (Compact)

public struct FloatingComposeButton: View {
    @EnvironmentObject private var navigationState: AppNavigationState

    public var body: some View {
        Button(action: {
            navigationState.isComposePresented = true
        }) {
            Image(systemName: "plus")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.accentColor)
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
        }
        .accessibilityLabel("Create new post")
    }
}

// MARK: - Keyboard Shortcuts Handler

/// Background view listening for global keyboard shortcuts.
public struct KeyboardShortcutsHandler: View {
    @ObservedObject var state: AppNavigationState

    public var body: some View {
        Group {
            Button("") { state.selectDestination(.timeline) }
                .keyboardShortcut("1", modifiers: .command)
            Button("") { state.selectDestination(.bookmarks) }
                .keyboardShortcut("2", modifiers: .command)
            Button("") { state.selectDestination(.profile) }
                .keyboardShortcut("3", modifiers: .command)
            Button("") { state.selectDestination(.settings) }
                .keyboardShortcut("4", modifiers: .command)
            Button("") { state.isComposePresented = true }
                .keyboardShortcut("n", modifiers: .command)
            Button("") { state.tabBarCoordinator.triggerRefresh(for: state.selectedDestination) }
                .keyboardShortcut("r", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Content Host & Modular Destination Seam

/// Pluggable destination host bridging navigation into Milestone 3 & Milestone 4 views.
public struct DestinationContentHost: View {
    public let destination: AppDestination
    @EnvironmentObject private var coordinator: TabBarCoordinator

    public var body: some View {
        ScrollViewReader { proxy in
            Group {
                switch destination {
                case .timeline:
                    TimelineContainerView()
                case .bookmarks:
                    BookmarksContainerView()
                case .profile:
                    ProfileContainerView()
                case .settings:
                    SettingsContainerView()
                }
            }
            .id("root_scroll_anchor")
            .onChange(of: coordinator.scrollToTopTriggers[destination]) { _, _ in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    proxy.scrollTo("root_scroll_anchor", anchor: .top)
                }
            }
        }
        .navigationTitle(destination.title)
        .navigationDestination(for: NavigationRoute.self) { route in
            RouteDestinationView(route: route)
        }
    }
}

// MARK: - Route Destination Routing & Container Views (M3 / M4 View Seams)

/// Dispatches strongly-typed NavigationRoute destinations to their corresponding container views.
public struct RouteDestinationView: View {
    public let route: NavigationRoute

    public init(route: NavigationRoute) {
        self.route = route
    }

    public var body: some View {
        switch route {
        case .postDetail(let postId):
            PostDetailContainerView(postId: postId)
        case .userProfile(let userId):
            UserProfileDetailContainerView(userId: userId)
        case .mediaLightbox(let url):
            MediaLightboxContainerView(url: url)
        }
    }
}

/// Container view for post conversation thread detail presentation.
public struct PostDetailContainerView: View {
    public let postId: String

    public init(postId: String) {
        self.postId = postId
    }

    public var body: some View {
        ContentUnavailableView(
            "Post Detail",
            systemImage: "bubble.left.and.bubble.right",
            description: Text("Post ID: \(postId)\nFull thread conversation and replies will render here.")
        )
        .navigationTitle("Post")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// Container view for user profile presentation pushed onto stack.
public struct UserProfileDetailContainerView: View {
    public let userId: String

    public init(userId: String) {
        self.userId = userId
    }

    public var body: some View {
        ProfileView(userId: userId)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }
}

/// Container view for full-screen media lightbox presentation.
public struct MediaLightboxContainerView: View {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public var body: some View {
        ContentUnavailableView(
            "Media Lightbox",
            systemImage: "photo.on.rectangle.angled",
            description: Text("Viewing media asset:\n\(url.absoluteString)")
        )
        .navigationTitle("Media")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Default Container Views (Ready for M3 / M4 View Integration)

public struct TimelineContainerView: View {
    public init() {}

    public var body: some View {
        TimelineView()
    }
}


public struct BookmarksContainerView: View {
    public init() {}

    public var body: some View {
        ContentUnavailableView(
            "Bookmarks",
            systemImage: "bookmark",
            description: Text("Saved posts will appear here.")
        )
    }
}

public struct ProfileContainerView: View {
    public init() {}

    public var body: some View {
        ProfileView(userId: nil)
    }
}

public struct SettingsContainerView: View {
    @StateObject private var viewModel: SettingsViewModel

    public init(viewModel: SettingsViewModel = SettingsViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        SettingsView(viewModel: viewModel)
    }
}

public struct ComposeModalHost: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var navigationState: AppNavigationState

    public init() {}

    public var body: some View {
        ComposeView {
            navigationState.isComposePresented = false
            navigationState.tabBarCoordinator.triggerRefresh(for: .timeline)
        }
    }
}
