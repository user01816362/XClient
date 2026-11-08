# XProject

XProject contains **XClient**, an independent native SwiftUI client, and **XKit**, its Swift networking and model packages. It is not an X.app wrapper and cannot access X.app's private account storage. The project is under development; endpoint compatibility, UI behavior, and the current working tree have not been verified end to end on iOS.

## Current status

- XClient still opens an isolated X web login and stores that separate session in the device-only Keychain. XKit now has a standalone OAuth PKCE flow coordinator, but onboarding does not use it yet; the X developer client ID and registered callback URI are not configured.
- Home, post detail, profiles, search, and single text-post requests have implementations, but their private endpoint identifiers and transaction signing are not confirmed against the current live web session. A captured native request does not establish that a separate web-session request will work.
- Settings is reached from the gear on your profile. Appearance uses system semantic colors with System, Light, and Dark choices; the downloaded-media cache control is also available.
- Replies, thread/media publishing, and undo repost are not ready. Bookmarks is a placeholder; other unsupported or unverified flows remain.
- Mock services and fixtures are used in tests and the headless smoke runner. Their success is not evidence of live X functionality.

See [current integration status](Doc/REAL_SESSION_INTEGRATION_STATUS.md) for the specific observations, scope and outstanding gaps. Avoid presenting the app as feature-complete or a drop-in replacement for X.

## Repository

| Path | Purpose |
| --- | --- |
| `XAPP/XClient/` | XClient Swift package, SwiftUI source, tests and iOS Xcode project. The package declares iOS 17 and macOS 14 minimums. |
| `sdks/XKit/` | Swift package containing XKit models, transport, authentication helpers, API services and test support; it declares iOS 16 and macOS 13 minimums. |
| `XAPP/Payload/`, `XAPP/X_12.38_dump/` | Local X app artifacts and static 12.38 research input. These are not a verified third-party API contract. |
| `exmaple/` | Reference projects, not part of XClient's implementation or evidence that its endpoints work. |
| `.github/workflows/build.yml` | GitHub Actions workflow for SDK/client tests, package builds, unsigned iOS archive and artifacts. Its release job can publish on configured events. |

## Building and testing

Use the GitHub Actions **Build** workflow for this workspace. The user has requested no local builds because Xcode is unavailable locally. The workflow includes SwiftPM tests, the mock-based headless smoke test and an unsigned iOS archive. A CI run builds a committed remote revision; it cannot build uncommitted local changes. Before triggering a run, inspect its publishing settings and event: the workflow can publish releases.

The current working-tree changes have not been built or tested in CI. A successful CI build would still not verify real X login, request acceptance, account isolation or visual behavior on a device.

## Documentation

- [Project architecture and feature status](Doc/PROJECT.md)
- [Integration evidence and open gaps](Doc/REAL_SESSION_INTEGRATION_STATUS.md)
- [SDK architecture](Doc/SDK_ARCHITECTURE.md)
- [Test infrastructure](Doc/TEST_INFRA.md) and [release test plan](Doc/TESTING_RELEASE_PLAN.md)
- [Security and privacy](Doc/SECURITY_PRIVACY.md)
- [Dump research method](Doc/DUMP_RESEARCH_METHOD.md)
- [Agent handoff](Doc/AGENT_HANDOFF.md)
- [Research sources](Doc/RESEARCH_SOURCES.md)
- [Native client architecture and rebuild audit](Doc/NATIVE_XCLIENT_REBUILD_AUDIT_2026-11-08.md)

The original requirements and early research plans are historical context; where they differ, the current integration status and code take precedence.
