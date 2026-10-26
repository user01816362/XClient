# Project: XClient Native Multiplatform Client

## Architecture
- **Multiplatform SwiftUI Application**: Pure native Swift/SwiftUI application targeting macOS (14+) and iOS (26+) located in `XAPP/XClient/`.
- **SDK Integration**: Links directly to `sdks/XKit` (`XKitModels`, `XKitTransport`, `XKitAuth`, `XKitAPI`) with 100% Swift 6 strict concurrency compliance (`Sendable`, `@MainActor`).
- **Offline Mock Preview State**: Comprehensive `MockDataProvider` providing deterministic user profiles, reverse-chronological timeline posts, replies, and bookmarks for zero-credential preview, interactive execution, and testing.
- **Adaptive Navigation**: Dynamic container responsive to platform size classes — compact bottom TabBar on iPhone, NavigationSplitView with collapsible Sidebar on iPad and macOS.
- **Liquid Glass Design System**: Dynamic type scaling, semantic color hierarchy (Light, Dark Dim, Dark Lights Out), translucent material layers with strict accessibility fallbacks (`accessibilityReduceTransparency`).
- **Dual-Mode Executable Runner**: `XClientApp` executable target launching interactive desktop window by default, and supporting `--verify` headless verification for automated testing and CI.
- **CI / Build Matrix**: GitHub Actions workflow compiling `sdks/XKit` and `XAPP/XClient` on `xcode-27` runner with SPM build caching.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| F1 | SPM Multiplatform Package & Toolchain | Swift 6 package manifest (`Package.swift`) targeting macOS 14+ and iOS 26+, shared library `XClient`, executable `XClientApp`, test target `XClientTests`, strict concurrency settings | M1 | ORIGINAL_REQUEST §R1, Survey 3 |
| F2 | Adaptive HIG Navigation Framework | Responsive navigation container: iPhone compact bottom TabBar, iPad split-view, macOS desktop Sidebar with keyboard shortcuts | M2 | ORIGINAL_REQUEST §R1, Survey 2 |
| F3 | Liquid Glass Appearance & Design Tokens | Glass materials, elevation hierarchy, dynamic type, theme modes (Light/Dim/Lights Out), `accessibilityReduceTransparency` fallback | M2 | ORIGINAL_REQUEST §R1, Survey 2 |
| F4 | Reverse-Chronological Timeline & Polling | Reverse-chronological post feed, pull-to-refresh, configurable background polling actor, unread posts buffer pill | M3 | ORIGINAL_REQUEST §R2, Survey 2 |
| F5 | Rich PostCard Component Hierarchy | 5-part card: Author row (avatar, verified badge, relative time), Body with active text ranges, Media presentation, Quoted card, Actions bar | M3 | ORIGINAL_REQUEST §R2, Survey 2 |
| F6 | Media Presentation & Download Pipeline | Media rendering, inline context menu with "Save to Photos" (iOS) / "Save to Downloads" (macOS), streaming URLSession download manager | M3 | ORIGINAL_REQUEST §R2, Survey 2 |
| F7 | User Profile Surface & Subtab Views | Parallax banner header, dynamic avatar collapse, bio, follower/following stats, joined date, and 4 tabbed subviews (Posts, Replies, Media, Likes) | M4 | ORIGINAL_REQUEST §R2, Survey 2 |
| F8 | Modern Post Composer & Threading | Modal compose sheet, character count ring gauge, thread nodes creation, draft persistence, publish confirmation | M4 | ORIGINAL_REQUEST §R2, Survey 2 |
| F9 | Settings Panel & Customization | Preferences for theme, Liquid Glass intensity slider, auto-refresh intervals, media cache purger, live sample card preview | M4 | ORIGINAL_REQUEST §R2, Survey 2 |
| F10 | XKit SDK Integration & Mock Data Provider | Integration with `sdks/XKit` services (`UsersService`, `PostsService`, `BookmarksService`, `TimelinesService`), Swift 6 strict concurrency, offline mock provider | M1 | ORIGINAL_REQUEST §R3, Survey 1 |
| F11 | macOS Executable Runner (`swift run XClientApp`) | Desktop application runner with dual-mode launch (interactive UI by default, `--verify` headless check for tests/CI) | M5 | ORIGINAL_REQUEST §R4, Survey 3 |
| F12 | CI/CD Workflow & Matrix Integration | Update `.github/workflows/build.yml` and root `build.yml` for SPM caching, compilation, tests, and verification on `xcode-27` | M5 | ORIGINAL_REQUEST §R4, Survey 3 |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Package Foundation, SDK Wiring & Offline Mock Data Engine | Create `XAPP/XClient/Package.swift`, link `sdks/XKit`, implement `MockDataProvider`, model wrappers, and service clients with Swift 6 strict concurrency | none | DONE |
| M2 | Liquid Glass Design System & Adaptive HIG Navigation | Implement Liquid Glass appearance tokens, materials, themes, accessibility fallbacks, and adaptive navigation container (iPhone TabBar vs iPad/macOS Sidebar) | M1 | DONE |
| M3 | Timeline Engine, Background Polling & Rich PostCard Components | Implement `TimelineView`, `TimelineViewModel`, background polling actor, unread pill, 5-part `PostCardView`, and Media presentation/download pipeline | M1, M2 | DONE |
| M4 | Profile, Compose & Settings Surfaces | Implement `ProfileView` with parallax header and 4 subtabs, `ComposeView` with character ring and threads, and `SettingsView` with preferences and cache management | M1, M2, M3 | DONE |
| M5 | Executable Runner, Local Verification & CI/CD Workflows | Implement `XClientApp` executable runner (dual-mode interactive/verify), update `.github/workflows/build.yml` and `build.yml` in lockstep, verify local compilation | M1, M2, M3, M4 | IN_PROGRESS |
| M6 | Final Milestone: Full E2E Test Suite & Adversarial Hardening | Execute 100% of E2E tests (Tiers 1-4) published in `TEST_READY.md`, followed by Tier 5 adversarial coverage hardening | M1-M5, TEST_READY.md | PLANNED |

## Interface Contracts

### M1 ↔ M2/M3/M4/M5: Data & Service Contracts
- **Mock Data Engine**:
  ```swift
  @MainActor
  public final class MockDataProvider: Sendable {
      public static let shared: MockDataProvider
      public var currentUser: XUser
      public var timelinePosts: [XPost]
      public var userPosts: [XPost]
      public var bookmarks: [XPost]
      public static func makeMockClient() -> XClient
  }
  ```
- **Service Protocol / Client Wrapper**:
  ```swift
  @MainActor
  public protocol XClientServiceProtocol: Sendable {
      func fetchHomeTimeline() async throws -> [XPost]
      func fetchUserProfile(id: String) async throws -> XUser
      func createPost(text: String) async throws -> XPost
      func bookmarkPost(id: String) async throws -> Bool
      func removeBookmark(id: String) async throws -> Bool
  }
  ```

### M2 ↔ M3/M4: Design System & Navigation Contracts
- **Liquid Glass Tokens**:
  ```swift
  public enum LiquidGlassStyle {
      case standard
      case elevated
      case prominent
  }
  public struct LiquidGlassModifier: ViewModifier { ... }
  ```
- **Adaptive Navigation Destinations**:
  ```swift
  public enum AppDestination: Hashable, CaseIterable, Identifiable, Sendable {
      case timeline
      case bookmarks
      case profile
      case settings
  }
  ```

### M3 ↔ M4/M5: Media & Timeline Contracts
- **Media Download Manager**:
  ```swift
  @MainActor
  public final class MediaDownloadManager: Sendable {
      public func downloadMedia(from url: URL, filename: String) async throws -> URL
      public func saveToPhotos(image: PlatformImage) async throws
      public func clearCache() async throws -> Int
  }
  ```
- **Polling Engine**:
  ```swift
  public actor TimelinePollingEngine {
      public func startPolling(interval: TimeInterval, onNewPosts: @Sendable @escaping ([XPost]) -> Void)
      public func stopPolling()
  }
  ```

## Code Layout
```
XAPP/XClient/
├── Package.swift
├── Sources/
│   ├── XClient/
│   │   ├── Navigation/
│   │   │   ├── AppNavigation.swift
│   │   │   ├── AdaptiveRootView.swift
│   │   │   └── TabBarCoordinator.swift
│   │   ├── DesignSystem/
│   │   │   ├── LiquidGlass.swift
│   │   │   ├── ColorTheme.swift
│   │   │   └── Typography.swift
│   │   ├── Models/
│   │   │   ├── PostItem.swift
│   │   │   ├── UserProfile.swift
│   │   │   └── MediaAttachment.swift
│   │   ├── Services/
│   │   │   ├── XClientService.swift
│   │   │   ├── MockDataProvider.swift
│   │   │   ├── PollingEngine.swift
│   │   │   └── MediaDownloadManager.swift
│   │   └── Views/
│   │       ├── Timeline/
│   │       │   ├── TimelineView.swift
│   │       │   └── TimelineViewModel.swift
│   │       ├── PostCard/
│   │       │   ├── PostCardView.swift
│   │       │   ├── AuthorView.swift
│   │       │   ├── PostBodyView.swift
│   │       │   ├── AttachmentView.swift
│   │       │   └── ActionButtonBar.swift
│   │       ├── Profile/
│   │       │   ├── ProfileView.swift
│   │       │   └── ProfileViewModel.swift
│   │       ├── Compose/
│   │       │   ├── ComposeView.swift
│   │       │   └── ComposeViewModel.swift
│   │       └── Settings/
│   │           ├── SettingsView.swift
│   │           └── SettingsViewModel.swift
│   └── XClientApp/
│       └── main.swift
└── Tests/
    └── XClientTests/
        ├── MockDataProviderTests.swift
        ├── NavigationTests.swift
        ├── TimelineTests.swift
        ├── PostCardTests.swift
        ├── ProfileTests.swift
        ├── ComposeTests.swift
        └── SettingsTests.swift
```
