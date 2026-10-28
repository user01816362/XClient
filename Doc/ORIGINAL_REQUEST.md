# Original User Request

> **Historical requirements:** This document preserves earlier requests and acceptance criteria, including repeated sections. They are not statements of current functionality; local-build and exposed polling/glass settings requirements have since changed. See [project overview](PROJECT.md) and [current integration status](REAL_SESSION_INTEGRATION_STATUS.md).

## 2026-10-15T04:56:25Z

Build **XClient**, a modern native SwiftUI client application for iPhone, iPad, and macOS located in `XAPP/XClient/` that connects to the `XKit` SDK. The client provides a complete native UI (adaptive navigation tabs, real-time updating reverse-chronological timeline, rich post cards with media download options, user profile views, composer, and customization settings) crafted according to modern Apple HIG and Liquid Glass principles with zero deprecated APIs.

Working directory: `/Users/user/Desktop/XProject`
Integrity mode: development

## Reference Material
- Local SDK: `sdks/XKit/` (XKitModels, XKitTransport, XKitAuth, XKitAPI)
- UI & Platform Guide: `APPLE_PLATFORM_UI.md`
- Static Analysis Findings: `XAPP/X_12.33_dump/` (URTTimelineStatusItem, Profile, Navigation seams)
- CI Workflow: `.github/workflows/build.yml` and `build.yml`

## Requirements

### R1. Native Multiplatform SwiftUI App Package (`XClient`)
Create a pure Swift Package Manager multiplatform app at `XAPP/XClient/` targeting macOS (14+) and iOS (26+).
- Support responsive adaptive navigation: tab bar for iPhone compact layout, sidebar with navigation split-view for iPad and macOS.
- Native Liquid Glass appearance styling, dynamic type scaling, and seamless light and dark mode support.
- Zero non-Apple third-party runtime dependencies; strictly native Swift and SwiftUI.

### R2. Core UI Surfaces & Dump-Informed Components
Implement all core application views inspired by first-party navigation structures observed in the app dump:
- **Timeline & Feed:** Reverse-chronological feed with pull-to-refresh and a configurable background polling loop to provide near real-time updates for new posts and replies.
- **Post Card Component:** Author avatar, display name, handle, verified badge, relative timestamps, formatted post body, and interactive action bar (reply, repost, like, bookmark, share).
- **Media Presentation & Download:** Dedicated media rendering for embedded images/media with an inline context menu to save or download media directly to the local system/Photos.
- **User Profile View:** Cover image header, profile avatar, user bio, follower/following counts, joined date, and tabbed subviews (Posts, Replies, Media, Likes).
- **Post Composer:** Modern modal compose sheet with character count ring, thread creation support, draft persistence, and publish confirmation.
- **Settings & Customization:** Preferences panel to configure theme (System, Light, Dark), Liquid Glass intensity, auto-refresh intervals, and local media cache management.

### R3. XKit SDK Integration & Swift 6 Concurrency
- Seamlessly wire `XClient` views and viewmodels to `sdks/XKit` services (`UsersService`, `PostsService`, `BookmarksService`, `TimelinesService`).
- Implement 100% Swift 6 strict concurrency compliance (`@MainActor` view models, `Sendable` types).
- Provide offline mock preview state for every major view and viewmodel so the application can be built, previewed, and tested without live API keys.

### R4. Automated Build & CI Integration
- Provide a macOS executable runner within `XAPP/XClient` so the full app interface can be launched and verified directly on the local machine with `swift run`.
- Update `.github/workflows/build.yml` and root `build.yml` to compile both `sdks/XKit` and `XAPP/XClient` on the `xcode-27` GitHub runner.

## Acceptance Criteria

### Package Compilation & Concurrency
- [ ] `XAPP/XClient` builds cleanly via `swift build` on the local macOS Command Line Tools with zero compilation errors.
- [ ] Strict concurrency check passes with no data-race warnings or deprecated API calls.

### UI Surfaces & Functional Verification
- [ ] `TimelineView`, `PostCardView`, `ProfileView`, `ComposeView`, `SettingsView`, and `AppNavigation` are fully implemented and functional.
- [ ] Real-time polling mechanism and media save/download features are built and wired to preferences.
- [ ] Offline mock data provider initializes default timeline and profile states for interactive execution.
- [ ] `swift run XClientApp` executes successfully and demonstrates the application launch.

### CI/CD Workflow
- [ ] GitHub Actions workflow files (`.github/workflows/build.yml` and `build.yml`) test and build `XKit` and `XClient` on `xcode-27`.


## 2026-10-16T02:58:04Z

Build **XClient**, a modern native SwiftUI client application for iPhone, iPad, and macOS located in `XAPP/XClient/` that connects to the `XKit` SDK. The client provides a complete native UI (adaptive navigation tabs, real-time updating reverse-chronological timeline, rich post cards with media download options, user profile views, composer, and customization settings) crafted according to modern Apple HIG and Liquid Glass principles with zero deprecated APIs.

Working directory: `/Users/user/Desktop/XProject`
Integrity mode: development

Resume and complete the project using the existing team work state in `.agents/teamwork/` (including `teamwork_preview_orchestrator_1/GATE_STATUS.md` and `progress.md`), inspect `XAPP/XClient`, verify all milestones, run and resolve any remaining reviews, challenger tests, and forensic audits, and bring the multi-agent teamwork system to full certified completion.

## Reference Material
- Local SDK: `sdks/XKit/` (XKitModels, XKitTransport, XKitAuth, XKitAPI)
- UI & Platform Guide: `APPLE_PLATFORM_UI.md`
- Static Analysis Findings: `XAPP/X_12.33_dump/` (URTTimelineStatusItem, Profile, Navigation seams)
- CI Workflow: `.github/workflows/build.yml` and `build.yml`
- Existing Orchestration State: `.agents/teamwork/` (orchestrator_1, GATE_STATUS.md, progress.md)

## Requirements

### R1. Native Multiplatform SwiftUI App Package (`XClient`)
Create a pure Swift Package Manager multiplatform app at `XAPP/XClient/` targeting macOS (14+) and iOS (26+).
- Support responsive adaptive navigation: tab bar for iPhone compact layout, sidebar with navigation split-view for iPad and macOS.
- Native Liquid Glass appearance styling, dynamic type scaling, and seamless light and dark mode support.
- Zero non-Apple third-party runtime dependencies; strictly native Swift and SwiftUI.

### R2. Core UI Surfaces & Dump-Informed Components
Implement all core application views inspired by first-party navigation structures observed in the app dump:
- **Timeline & Feed:** Reverse-chronological feed with pull-to-refresh and a configurable background polling loop to provide near real-time updates for new posts and replies.
- **Post Card Component:** Author avatar, display name, handle, verified badge, relative timestamps, formatted post body, and interactive action bar (reply, repost, like, bookmark, share).
- **Media Presentation & Download:** Dedicated media rendering for embedded images/media with an inline context menu to save or download media directly to the local system/Photos.
- **User Profile View:** Cover image header, profile avatar, user bio, follower/following counts, joined date, and tabbed subviews (Posts, Replies, Media, Likes).
- **Post Composer:** Modern modal compose sheet with character count ring, thread creation support, draft persistence, and publish confirmation.
- **Settings & Customization:** Preferences panel to configure theme (System, Light, Dark), Liquid Glass intensity, auto-refresh intervals, and local media cache management.

### R3. XKit SDK Integration & Swift 6 Concurrency
- Seamlessly wire `XClient` views and viewmodels to `sdks/XKit` services (`UsersService`, `PostsService`, `BookmarksService`, `TimelinesService`).
- Implement 100% Swift 6 strict concurrency compliance (`@MainActor` view models, `Sendable` types).
- Provide offline mock preview state for every major view and viewmodel so the application can be built, previewed, and tested without live API keys.

### R4. Automated Build & CI Integration
- Provide a macOS executable runner within `XAPP/XClient` so the full app interface can be launched and verified directly on the local machine with `swift run`.
- Update `.github/workflows/build.yml` and root `build.yml` to compile both `sdks/XKit` and `XAPP/XClient` on the `xcode-27` GitHub runner.

## Acceptance Criteria

### Package Compilation & Concurrency
- [ ] `XAPP/XClient` builds cleanly via `swift build` on the local macOS Command Line Tools with zero compilation errors.
- [ ] Strict concurrency check passes with no data-race warnings or deprecated API calls.

### UI Surfaces & Functional Verification
- [ ] `TimelineView`, `PostCardView`, `ProfileView`, `ComposeView`, `SettingsView`, and `AppNavigation` are fully implemented and functional.
- [ ] Real-time polling mechanism and media save/download features are built and wired to preferences.
- [ ] Offline mock data provider initializes default timeline and profile states for interactive execution.
- [ ] `swift run XClientApp` executes successfully and demonstrates the application launch.

### CI/CD Workflow
- [ ] GitHub Actions workflow files (`.github/workflows/build.yml` and `build.yml`) test and build `XKit` and `XClient` on `xcode-27`.
