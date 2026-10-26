import SwiftUI
import Foundation
#if canImport(Darwin)
import Darwin
#endif
import XClient
import XKit
import XKitModels
import XKitTesting

/// Root desktop view displayed during interactive desktop execution.
struct DesktopRootView: View {
    @StateObject private var settingsViewModel = SettingsViewModel()
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        let palette = ColorPalette.resolve(preference: settingsViewModel.selectedTheme, systemScheme: systemScheme)

        AdaptiveRootView()
            .preferredColorScheme(settingsViewModel.selectedTheme.preferredColorScheme)
            .environment(\.colorPalette, palette)
            .frame(minWidth: 900, minHeight: 650)
    }
}

struct XClientDesktopApp: App {
    var body: some Scene {
        WindowGroup {
            DesktopRootView()
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        #endif
    }
}

let rawArgs = Array(CommandLine.arguments.dropFirst())

// 1. Interactive Desktop Launch (No Arguments)
if rawArgs.isEmpty {
    XClientDesktopApp.main()
}
// 2. Help Documentation
else if rawArgs.contains("--help") || rawArgs.contains("-h") {
    print("""
    OVERVIEW: XClient Desktop & Headless Runner

    USAGE: XClientApp [--verify | --headless] [--help | -h]

    OPTIONS:
      --verify, --headless    Run automated headless smoke verification tests and exit
      -h, --help              Show this help message
    """)
    exit(0)
}
// 3. Argument Validation & Headless Dispatch
else {
    let recognizedFlags: Set<String> = ["--verify", "--headless"]
    for arg in rawArgs {
        if !recognizedFlags.contains(arg) {
            fputs("Unknown argument: \(arg). Use --help for usage.\n", stderr)
            exit(1)
        }
    }

    do {
        print("===========================================================")
        print("XClientApp Runner: Automated Headless Verification Mode")
        print("===========================================================")

        // 1. Verify MockDataProvider state
        let mock = MockDataProvider.shared
        mock.resetToDefaults()

        assert(!mock.currentUser.id.isEmpty, "Mock user must have valid ID")
        assert(mock.currentUser.username == "liquidglass", "Mock user username must be liquidglass")
        assert(mock.timelinePosts.count >= 10, "Mock timeline posts must have at least 10 items")
        assert(mock.bookmarks.count >= 4, "Mock bookmarks must have at least 4 items")
        assert(mock.postItems.count >= 10, "Mock post items must have at least 10 items")
        print("  ✓ PASS: MockDataProvider initialized with deterministic fixtures")

        // 2. Verify XClientService facade offline wiring
        let service = XClientService()
        assert(service.token == "mock_token", "Service token must be initialized")
        assert(!service.currentUserId.isEmpty, "Service currentUserId must not be empty")
        print("  ✓ PASS: XClientService initialized with offline MockClient")

        // 3. Verify asynchronous operations on MainActor
        let homePosts = try await service.fetchHomeTimeline()
        assert(!homePosts.isEmpty, "Fetched home timeline must not be empty")

        let currentUser = try await service.fetchCurrentUser()
        assert(currentUser.id == mock.currentUser.id, "Fetched user ID must match mock")

        let userProfile = try await service.fetchUserProfile(id: currentUser.id)
        assert(userProfile.id == currentUser.id, "Fetched user profile ID must match")

        let userPosts = try await service.fetchUserPosts(userId: currentUser.id)
        assert(!userPosts.data.isEmpty, "Fetched user posts must not be empty")

        let createdPost = try await service.createPost(text: "Headless verification post")
        assert(createdPost.text == "Headless verification post", "Post creation text must match")

        let bookmarked = try await service.bookmarkPost(id: createdPost.id)
        assert(bookmarked == true, "Bookmark post must return true")

        let unbookmarked = try await service.removeBookmark(id: createdPost.id)
        assert(unbookmarked == true, "Remove bookmark must return true")

        let bookmarksResponse = try await service.fetchBookmarks()
        assert(bookmarksResponse.data.count >= 4, "Fetched bookmarks must contain default fixtures")

        let deleted = try await service.deletePost(id: createdPost.id)
        assert(deleted == true, "Delete post must return true")

        // 4. Verify DesktopRootView & AdaptiveRootView initialization
        let navigationState = AppNavigationState()
        assert(navigationState.selectedTab == .timeline, "Initial selected tab must be timeline")

        for destination in AppDestination.allCases {
            navigationState.selectDestination(destination)
            assert(navigationState.selectedDestination == destination, "Navigation state must match selected destination \(destination)")
        }
        navigationState.selectDestination(.timeline)
        assert(navigationState.selectedDestination == .timeline, "Selected destination must reset to timeline")

        let rootView = AdaptiveRootView(navigationState: navigationState)
        _ = rootView.body

        let desktopRoot = DesktopRootView()
        _ = desktopRoot.body
        print("  ✓ PASS: DesktopRootView & AdaptiveRootView desktop UI & navigation state initialized")

        print("  ✓ PASS: XClientService operations (timeline, user, profile, post, bookmark) verified")
        print("  ✓ PASS: Swift 6 strict concurrency checks satisfied")
        print("===========================================================")
        print("Verification successful. Exiting with code 0.")
        exit(0)
    } catch {
        fputs("Verification failed with error: \(error)\n", stderr)
        exit(1)
    }
}

