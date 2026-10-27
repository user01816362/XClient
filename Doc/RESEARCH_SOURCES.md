# Research sources and evidence notes

**Checked:** 2026-10-15. These links are first-party documentation unless explicitly labeled as a local reference checkout. Re-open them before implementation because both platform APIs and X access/policy can change.

## X API and policy

- [X Developer documentation index](https://docs.x.com/llms.txt) — indexes API v2, authentication, tools, changelog, OpenAPI, and official XDK documentation.
- [About the X API](https://docs.x.com/x-api/getting-started/about-x-api) — capability families, v2 versus legacy v1.1, resources, and pay-per-usage model.
- [X API v2 endpoint index](https://docs.x.com/x-api/llms.txt) — current endpoint/reference catalog; use this rather than searching arbitrary repositories for endpoint names.
- [X OpenAPI specification](https://docs.x.com/openapi.json) — machine-readable contract to snapshot/diff after checking the current docs.
- [OAuth 2.0 Authorization Code with PKCE](https://docs.x.com/fundamentals/authentication/oauth-2-0/authorization-code) — public-client/native-app description, scopes, access/refresh token behavior.
- [Timelines](https://docs.x.com/x-api/posts/timelines/introduction) — documents the reverse-chronological home timeline, most recent 3,200 posts or 7 days, and explicitly excludes algorithmic ranking.
- [Bookmarks](https://docs.x.com/x-api/posts/bookmarks/introduction) — list/add/remove operations and app/user authorization prerequisites.
- [Developer Guidelines](https://docs.x.com/developer-guidelines) — official API-only requirement, scraping/browser automation prohibition, content display/data obligations, AI-related rules, rate/redistribution restrictions. Review the linked Developer Agreement for the actual applicable terms.
- [Tools and libraries](https://docs.x.com/tools-and-libraries) — X lists Swift libraries Twift and TwitterAPIKit as community libraries not maintained by X; evaluate maintenance, license, auth, and coverage independently.
- [X API changelog](https://docs.x.com/changelog) — release monitoring source.

## Apple platform development

- [SwiftUI technology overview](https://developer.apple.com/documentation/technologyoverviews/swiftui) — shared SwiftUI app model and platform support.
- [Configuring a multiplatform app target](https://developer.apple.com/documentation/Xcode/configuring-a-multiplatform-app-target) — shared target tradeoffs and platform customization.
- [Swift 6 strict concurrency adoption](https://developer.apple.com/documentation/swift/adoptingswift6) — enable concurrency checking to catch data races at compile time; migration can be incremental.
- [ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession) — system web authentication session and callback handling.
- [Liquid Glass overview](https://developer.apple.com/documentation/technologyoverviews/liquid-glass) — current design overview and platform direction.
- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) — standard components, accessibility/display testing, and judicious custom effects.
- [Toolbar Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/toolbars) — action grouping and native toolbar behavior.
- [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files) — data collection and required-reason API declarations for apps and SDKs.
- [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/) — App Store Connect privacy disclosure requirements.

## Local reference projects (not authoritative API sources)

- [`exmaple/DiscordKit/`](exmaple/DiscordKit/) — copied Discord SDK reference. Its local `Package.swift` shows separate core, client, and bot products; confirm license and current upstream state before reuse.
- [`exmaple/Swiftcord-2/`](exmaple/Swiftcord-2/) — copied Swiftcord README/assets. Use for high-level UI/product study only until its actual source revision and license are inspected.
- [`XAPP/X_12.33_dump/README.txt`](XAPP/X_12.33_dump/README.txt) — local dump provenance summary. Static app internals are not official X API contracts.

## Evidence rule

When sources disagree, prioritize current X/Apple documentation and machine-readable official specs for their stated scope. If the exact API entitlement, pricing, or permission is account-specific, the Developer Console and a controlled test are required. Community repositories can help identify questions and implementation patterns, but cannot validate access permission or supersede official policy.
