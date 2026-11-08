# Native XClient rebuild audit

**Date:** 2026-11-08
**Scope:** XProject source, current project documentation, local build environment, current X app observation in Ophanim, Apple platform guidance, and current X API documentation.
**Code changes:** Audit, first native-appearance pass, and portable OAuth flow coordinator described below.
**Build/tests:** Not run. The workspace instructions say to use GitHub Actions rather than a local build, and the active machine has Command Line Tools but no selected Xcode.

## Decision

XProject already contains a native SwiftUI client shell and a separately packaged XKit SDK. The right product description is an **independent native X client**, rather than a wrapper that embeds or reuses the installed X app. A separate iOS app cannot read the installed X app's private files or session: iOS gives third-party apps separate sandbox containers and only permits cross-app access through explicit system sharing mechanisms. See [Apple's iOS app security overview](https://support.apple.com/guide/security/security-of-runtime-processes-in-ios-ipados-and-visionos-sec15bfe098e/web).

For a stable native client, XKit should use X's documented API and OAuth authorization code with PKCE. The current client instead mixes that path with X web cookies, guest tokens, private GraphQL IDs, and a locally generated web transaction header. Those private calls are not established contracts for a third-party client. X's current [Developer Guidelines](https://docs.x.com/developer-guidelines) ask developers to use the official API and disallow scraping/browser automation.

The central product limit is the Home feed. X's documented authenticated Home timeline is reverse chronological and excludes algorithmic ranking; it cannot provide the first-party For You experience. X documents that Home endpoint for OAuth 1.0a user context or OAuth 2.0 PKCE in its [Timelines documentation](https://docs.x.com/x-api/posts/timelines/introduction). Build the app around the documented features that X grants to the registered developer app; do not promise full X app parity.

## What exists in the repository

## First native-appearance pass

- The app-facing palette now resolves through UIKit/AppKit semantic system colors, so backgrounds, labels, and separators adapt to light/dark appearance and system contrast. The Appearance picker offers System, Light, and Dark; the old two dark preference values are not offered and now render with the same semantic Dark palette.
- Post cards use the normal semantic card background. The unread control and post-reply bar use SwiftUI system materials. The media play control uses a material surface without the previous custom white rim and shadow.
- Avatar fallbacks now use a neutral system surface. The unused settings sample preview with a vivid X-style gradient was removed.
- The UI keeps a `ColorPalette` role layer so later customization can be added without spreading color literals across views. No custom theme editor or extra palette was added.
- `LiquidGlass.swift` and glass-intensity persistence still exist as compatibility/test-facing code, but no app screen calls its custom glass modifiers and Settings no longer presents a glass control. Removing that stale API cleanly requires a separate test/API migration; it is not claimed as complete here.
- The original uncommitted `TimelineViewModel.swift` change was preserved.

## First XKit auth step

`XKitAuth/OAuthFlow.swift` now composes the existing PKCE, authorize URL, and token exchange code. It rejects a malformed redirect, duplicate/missing state, state mismatch, provider error, and duplicate/missing code before token exchange. It contains no app client ID or secret. This is a portable SDK layer only; it is not connected to `ASWebAuthenticationSession`, Keychain refresh-token persistence, or onboarding.

### SDK

`sdks/XKit` is already separated into model, transport, authentication, API, testing, and CLI targets. `XKitAuth` contains PKCE generation, authorization URL construction, and token exchange/refresh code. `OAuthFlow` now composes those pieces and validates callback origin, unique state, and a single authorization code before exchange. This remains an SDK helper; it is not the login path used by XClient today.

`XKitAPI` contains both documented v2 services and `GraphQLTimelineService`, whose source labels it as reverse-engineered and hard-codes private web GraphQL IDs. `XKitTransport/ClientTransactionSigner.swift` also constructs headers for the private web request path. Keep XKit's public API modules as the supported direction; retire the private web-session and guest request path as each screen is migrated.

`XClientService.swift` combines authentication mode checks, mock/live selection, public API calls, private GraphQL calls, parsing, and fallback decisions. The next structure should put each feature behind a small typed repository interface, with the live X API adapter and the mock adapter injected at the app composition point. Auth state and transport should be owned by separate modules, not reconstructed by each view model.

### Authentication and account storage

`TwitterWebLoginView.swift` presents `x.com` in a `WKWebView`, extracts `auth_token` and `ct0` from the web cookie store, and has a manual cookie entry path. `SessionManager.Account` stores web tokens, CSRF values, and an optional raw cookie header. This does not share X's native app account; it creates and retains a separate web-session credential.

The PKCE implementation is still disconnected from onboarding. X documents Native Apps as public OAuth clients that cannot protect an embedded client secret. Its PKCE docs say access tokens last two hours by default and that `offline.access` is required for refresh tokens. Apple documents `ASWebAuthenticationSession` as the system web authentication mechanism with a callback delivered to the initiating app. The migration should connect `OAuthFlow` to `ASWebAuthenticationSession`, request only needed scopes, and store/refresh tokens in Keychain. No client ID, registered callback URL, or X developer app configuration was found in the XClient project settings; those must be configured before real login can be verified.

Sources: [X OAuth 2.0 PKCE](https://docs.x.com/fundamentals/authentication/oauth-2-0/authorization-code), [Apple ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession).

### App and UI

XClient already has a native adaptive navigation foundation: an iPhone `TabView`, regular-width `NavigationSplitView`, and typed navigation routes in `AdaptiveRootView.swift` and `AppNavigation.swift`. Retain and simplify that structure rather than rebuilding the app shell from scratch.

Current gaps visible in source and the project status docs:

- Primary destinations are Timeline, Bookmarks, and Profile; Bookmarks currently shows a placeholder. Search is presented as a sheet.
- `AdaptiveRootView.swift` owns many unrelated sheet, navigation, guest-banner, and destination behaviors in one large file.
- The first appearance pass now uses dynamic UIKit/AppKit system colors and SwiftUI materials in active screens. Fixed hex snapshots remain in `ColorTheme` for the existing contrast-analysis suite, and the unused custom modifier implementation remains isolated in `LiquidGlass.swift`; neither is used by current post cards or timeline controls.
- Visible strings are embedded in Swift source; no app localization resource catalog is present.
- Many views use fixed point font sizes. Accessibility labels exist on some controls, but Dynamic Type and accessibility coverage are inconsistent.
- Several screens/actions still rely on mocks or are explicitly incomplete: Bookmarks UI, replies, thread and media publishing, undo repost, and live endpoint behavior.

For the requested neutral first release, use system/light/dark appearance, semantic system backgrounds/labels/separators, standard SwiftUI navigation and controls, and SF Symbols. Avoid fixed hex colors and custom glass decoration. Keep a small semantic styling interface as a future customization seam, but do not add a color editor or extra themes now. Apple says dynamic semantic system colors adapt across appearance and contrast settings, and recommends avoiding app-specific appearance settings when the system preference can be followed. See [Apple Color guidance](https://developer.apple.com/design/human-interface-guidelines/color) and [Dark Mode guidance](https://developer.apple.com/design/human-interface-guidelines/dark-mode).

## Ophanim observation of X 12.41

This was a partial live observation, not an API contract audit. Ophanim lists X `com.atebits.Tweetie2` version 12.41. The Home screen showed For You, Following, Add, and a custom timeline; the bottom navigation exposed Home, Search/Explore, Communities, Notifications, Chat, and Profile. The profile view used a large header, account actions, profile timeline tabs, and post cards. Runtime hierarchy included `T1AppSplitViewController`, `HomeTimelineContainerViewController`, `T1TabView`, `T1URTViewController`, and `TFNTableView`.

The current local static dump is X 12.38, while Ophanim's installed runtime is 12.41. Do not use a 12.38 selector or class observation as proof of 12.41 runtime behavior.

The network capture exposed only a partial event projection. It contained traffic to `api.twitter.com`, `x.com`, `twitter.com`, `video.twimg.com`, and `firebaselogging-pa.googleapis.com`; observed requests had mixed 200 and 403 statuses. Request paths and response semantics were not available in this projection, so this does not establish endpoint contracts, request purpose, or a complete analytics inventory. `launch_status` reported `running=false` while UI and event tools returned data; treat the capture as partial and do not infer request causality from it.

## Size and build facts

The local workspace contains about 626 MB in `XAPP/Payload`, 108 MB in `XAPP/X_12.38_dump`, and 380 MB in the copied `sdks/iPhoneOS27.0.sdk`. All three paths are ignored by Git and have zero tracked files. The CI package script copies XKit/XClient source and the archived XClient app; it does not copy those local research assets into the app archive. Therefore these folder sizes are not evidence of installed XClient size. Measure archive and installed sizes from a clean, current Xcode build before making a size claim.

The active developer directory is Command Line Tools. `swift --version` reports Apple Swift 6.4.2; `xcodebuild -version` fails because full Xcode is not selected. Existing repository instructions say not to run local builds. The current working tree also has an existing edit in `XAPP/XClient/Sources/XClient/Views/Timeline/TimelineViewModel.swift`; it was left untouched.

## Recommended implementation order

1. **Set the support contract:** documented X API endpoints only; list the features and scopes X's developer app actually supports. Mark For You and any unavailable first-party-only surfaces as unsupported.
2. **Finish official auth:** configure the registered X public-client ID and redirect URI, wire XKit PKCE through `ASWebAuthenticationSession`, then remove manual cookies, raw cookie storage, guest-token and embedded WebView-login behavior from the supported product path. Keep account refresh, logout, revocation, and Keychain failures explicit.
3. **Make XKit feature modules narrow and testable:** public endpoint request/response models, typed repositories, injected transport and auth; no private GraphQL IDs in production services. Preserve mocks as explicit test/preview adapters, never live fallbacks.
4. **Repair one read surface at a time:** start with an OAuth-supported timeline, profile lookup, post detail, and search. Add pagination, rate-limit handling, and real API response fixtures tagged with their official docs. Do not show an operation in navigation until it works with the granted scopes.
5. **Simplify the SwiftUI shell:** keep adaptive navigation, split large root coordination into focused modules, use semantic system colors and standard controls, support Dynamic Type and VoiceOver, and move visible text to Apple's localization resources.
6. **Prove real behavior on current Xcode/iOS:** CI package tests and archive are necessary but insufficient. Run login, account switching, representative reads/writes, errors, appearance, and accessibility checks with a controlled developer app/account. Record archive size and network usage from that build.

## Independent review

Three read-only agents reviewed the SDK/API, UI/UX, and overall architecture independently. All agreed that the current tree is a native-client prototype with useful SwiftUI and PKCE foundations, but not a verified full X client. Their main recommendation was to remove the private web-session dependency from the supported path, use documented OAuth/API contracts, keep only capability-backed screens, and simplify the color/navigation layer. No agent changed files or built the project.
