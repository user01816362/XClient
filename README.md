# XProject

Native Swift X client and reusable X API SDK — research and implementation plan

**Status:** planning only. No app source, credentials, or API requests have been added yet.
**Research checked:** 2026-10-15. Recheck current X and Apple documentation before implementation; API access, pricing, scopes, policies, and SDK guidance can change.

## Goal

Build a small, privacy-conscious, native Swift client for iPhone, iPad, and macOS, powered by a reusable Swift Package Manager SDK named **XKit**. Start with documented X APIs and features that can be verified end to end. Treat X 12.33 app-dump analysis as a separate research stream for understanding feature gaps; a class dump is not an API contract and does not itself authorize or make private endpoints suitable for release.

This is a new client, not an X app wrapper, XEnhancer update, or plugin loader for the installed X app. It will have its own UI, login flow, networking, local storage, and limitations.

## Product principles

- Native SwiftUI surfaces, adapted to iPhone, iPad, and Mac instead of forcing one layout everywhere.
- A platform-neutral SDK that does not import SwiftUI, UIKit, or AppKit.
- Official X API as the **only** production access path. Prefer v2 for new work; investigate v1.1 only when current official docs say a required capability remains there.
- No embedded X account passwords, copied app secrets, extracted tokens, or private API dependencies in the released SDK.
- Minimize collection: no analytics by default, no credential or private-content logs, least-privilege OAuth scopes, local Keychain-backed account credentials.
- Fail closed on uncertain API behavior. Record evidence and open questions instead of asserting parity with X’s app.
- Build with the current stable Apple toolchain and SDKs at implementation time; avoid deprecated APIs and verify availability before adoption.

## Project folders

| Path | Current contents / intended use |
|---|---|
| `XAPP/X_12.33_dump/` | Local static analysis artifacts for the X 12.33 binary. Use only as a versioned research input. |
| `sdks/iPhoneOS27.0.sdk/` | A 381 MB SDK bundle is present. However, the active developer directory is Command Line Tools and `xcodebuild -version` currently fails because Xcode is not selected/available. Do not treat this as a ready iOS/iPadOS app build environment. See [environment inventory](ENVIRONMENT_INVENTORY.md). |
| `exmaple/DiscordKit/` | Reference checkout. Study package boundaries, public API ergonomics, documentation, and tests. Do not assume it is an official X pattern or copy code without reviewing its license. |
| `exmaple/Swiftcord-2/` | Swiftcord reference README/assets. The README describes a native SwiftUI Discord client; inspect its current source and license before using it as an implementation reference. |
| `sdks/XKit/` | Planned home for XKit Swift packages (not scaffolded yet). |
| `XAPP/XClient/` | Planned home for the native client app (not scaffolded yet). |

## Read first

1. [Project plan](PROJECT_PLAN.md) — phases, evidence gates, exit criteria.
2. [SDK architecture](SDK_ARCHITECTURE.md) — package boundaries and API design rules.
3. [Official API coverage](API_CAPABILITY_MATRIX.md) — what is documented and what remains unverified.
4. [Dump research method](DUMP_RESEARCH_METHOD.md) — safe, reproducible analysis rules.
5. [Security and privacy](SECURITY_PRIVACY.md) — authentication, secrets, local data, telemetry.
6. [Apple platform and UI plan](APPLE_PLATFORM_UI.md) — SwiftUI, availability, Liquid Glass, platform adaptation.
7. [Testing and release plan](TESTING_RELEASE_PLAN.md) — contract tests, integration gates, release criteria.
8. [Agent handoff](AGENT_HANDOFF.md) — task boundaries and evidence requirements for future agents.
9. [`research/outline.yaml`](research/outline.yaml) and [`research/fields.yaml`](research/fields.yaml) — structured research queue and evidence fields.
10. [Environment inventory](ENVIRONMENT_INVENTORY.md) — current verified local setup and build blocker.
11. [Research sources](RESEARCH_SOURCES.md) — first-party docs and local reference provenance.

## Verified starting facts

- Apple documents SwiftUI and a shared multiplatform target for iOS, iPadOS, and macOS. Platform-specific experience and API availability still need explicit checks. [SwiftUI overview](https://developer.apple.com/documentation/technologyoverviews/swiftui), [multiplatform target guidance](https://developer.apple.com/documentation/Xcode/configuring-a-multiplatform-app-target).
- Apple’s current guidance recommends adopting Liquid Glass through standard system components and using custom glass effects sparingly. [Liquid Glass overview](https://developer.apple.com/documentation/technologyoverviews/liquid-glass), [adoption guidance](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass).
- Apple documents Swift 6 strict concurrency as a compile-time aid for finding data races. Swift 6 language mode should be enabled deliberately and packages migrated with compiler evidence. [Swift 6 concurrency adoption](https://developer.apple.com/documentation/swift/adoptingswift6).
- X documents API v2 resources including posts, users, Spaces, DMs, and lists, and identifies v1.1 as legacy with some specialized endpoints still there. The exact callable surface is endpoint-, scope-, and account-access-dependent. [About the X API](https://docs.x.com/x-api/getting-started/about-x-api), [X API documentation index](https://docs.x.com/llms.txt).
- X’s published native-app authorization flow is OAuth 2.0 Authorization Code with PKCE. Its docs identify native apps as public clients and describe refresh-token behavior when `offline.access` is granted. [OAuth 2.0 PKCE](https://docs.x.com/fundamentals/authentication/oauth-2-0/authorization-code).
- X’s current documentation index lists official Python and TypeScript XDKs. It does not list an official Swift XDK in that index at research time; recheck before deciding whether to create or adopt one. [X docs index](https://docs.x.com/llms.txt).

## Non-goals for the initial project

- Claiming feature parity with X’s first-party iOS app.
- Using X app credentials, session cookies, or undocumented internal API requests in XKit.
- Reproducing X’s UI assets or brand in a way that implies endorsement.
- Loading arbitrary native plugin binaries or executing AI-generated code inside the app.
- Adding an AI code-writing agent before XKit’s public contracts, sandbox, permissions, and review process exist.

## Current decision

Proceed with an **official-API-first SDK prototype**, then decide whether the API and access model can support the minimum native client. Keep private-endpoint findings in a separate evidence ledger and only revisit their use after policy and legal review. The project should stop or narrow scope if required features cannot be verified through documented, permitted APIs.
