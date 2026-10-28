# XClient project overview

**Status:** implementation in progress. The current source has not been validated by CI or an iOS device since the recent changes. A SwiftUI view or SDK method being present does not establish that an X endpoint accepts it.

## Components

- `XAPP/XClient` contains the shared SwiftUI library, the app entry point, an iOS Xcode project, and tests. Its package and project declare iOS 17 and macOS 14 minimums.
- `sdks/XKit` contains models, URLSession transport, OAuth helpers, API services and mock transport. It includes public API v2 services and experimental private web-session calls. The SDK declares iOS 16 and macOS 13 minimums.
- XClient's visible primary destinations are Home, Bookmarks and Profile. The profile gear presents Settings. The Bookmarks screen is currently a placeholder.
- Settings exposes appearance, downloaded-media cache management and the app version. The system dark preference uses the black palette; the dim theme remains selectable. The former glass-intensity and polling controls are not exposed because they were not connected to the claimed app behavior.
- Login uses X's web flow and validates a returned session using the authenticated account endpoint. Account sessions are stored as an encoded collection in the device-only Keychain, with a migration path from UserDefaults. Multi-account and migration behavior remain unverified on a device.

## Feature state

| Area | Implemented source | Remaining evidence or work |
| --- | --- | --- |
| Login | WebKit login, account verification, session storage and account switching | Test X's current login, providers, Keychain failures, account switch and logout on iOS. This is not native OAuth parity. |
| Home | Timeline requests, parsing, pagination UI and refresh | User reports the timeline fails. Web request IDs, transaction signing, response shape and real-session behavior are unverified. |
| Post and profile | Post cards, profile UI, post-detail parsing and actions | Confirm requests, full media, authors, conversation nesting, pagination and actual server outcomes. |
| Compose | Single text-post request and drafts | Replies, media, and threads are not available; incomplete drafts are preserved rather than sent as unrelated posts. |
| Media | Download manager, local cache and platform export paths | Test download, cancellation, cache clearing, format handling and permissions on device. |
| Appearance | Light, system dark/black, optional dim and black themes | Verify visual behavior and accessibility across supported devices and settings. |
| CI | `.github/workflows/build.yml` tests packages, runs a mock smoke runner, archives iOS and packages artifacts | Run against the actual changed revision; this has not happened yet. CI does not prove live X behavior. |

Details and capture findings: [REAL_SESSION_INTEGRATION_STATUS.md](REAL_SESSION_INTEGRATION_STATUS.md). The former milestone table claimed several features were done based on mock-driven work; those claims are superseded by the states above.
