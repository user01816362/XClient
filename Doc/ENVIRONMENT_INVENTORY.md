# Local environment inventory

**Checked:** 2026-10-15. Read-only inspection; no build or API request was run.

## Verified state

| Item | Observation | Consequence |
|---|---|---|
| Workspace | `/Users/user/Desktop/XProject` exists and contains `XAPP`, `sdks`, and `exmaple` | Planning assets are in the requested location. The folder spelling `exmaple` is preserved. |
| Apple SDK bundle | `sdks/iPhoneOS27.0.sdk` exists and reports about 381 MB | Bundle contents exist locally; this alone does not provide Xcode, simulators, signing, or a supported build setup. |
| Active developer directory | `xcode-select -p` reports `/Library/Developer/CommandLineTools` | Active toolchain is Command Line Tools, not a selected full Xcode developer directory. |
| Xcode build tool | `xcodebuild -version` exits with: `tool 'xcodebuild' requires Xcode, but active developer directory ... is a command line tools instance` | App build/sign/archive is currently blocked until Xcode is installed/selected. |
| Swift compiler | `swift --version` reports Apple Swift 6.4.0 (`swift-driver 1.168.6`) targeting `arm64-apple-macosx27.2.0` | A Swift compiler is present. This does not prove iOS/iPadOS app builds will work in this environment. |
| X app dump | `XAPP/X_12.33_dump/README.txt` identifies a full dump generated 2026-10-11 and records a binary hash and artifacts | Verify source, hashes, tool versions, and app build independently before each analysis. |
| DiscordKit example | `exmaple/DiscordKit/Package.swift` defines `DiscordKitCore`, `DiscordKit`, and `DiscordKitBot`, and declares Swift tools 5.6, macOS 11, iOS 15 | Useful package-organization study. It is not an X SDK and its declared targets do not establish current compatibility. |
| Swiftcord example | `exmaple/Swiftcord-2/README.md` describes a native SwiftUI macOS Discord app and labels the checked-out documentation as the newer project README; it points legacy code to `main` | Treat as a design/reference source. Check source branch and license before code reuse. |

## Required setup before implementation

1. Install/select full stable Xcode appropriate to the project and current Apple SDKs.
2. Record `xcodebuild -version`, `swift --version`, `xcode-select -p`, available SDKs and simulator runtimes.
3. Verify `xcodebuild -showsdks` and a minimal SwiftPM package build for macOS and iOS Simulator.
4. Confirm signing and intended distribution path (App Store, TestFlight, or other) separately from API feasibility.
5. Choose minimum OS versions from user requirements and API availability, not from the copied SDK directory.
6. Keep local `X` developer credentials outside this workspace and source control.

## Not verified yet

- That an Xcode.app bundle is installed elsewhere on this machine.
- That the copied iPhoneOS SDK bundle is complete, unmodified, redistributable, or directly usable with the current compiler.
- That any X API developer app has been approved or has access to specific endpoints.
- That the app can be signed, installed, or distributed through a specific channel.
- That the current Swiftcord/DiscordKit checkouts match the latest remote commits.
