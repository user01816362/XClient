# Apple platform, Swift, and UI plan

## Platform strategy

Target iPhone, iPad, and Mac with SwiftUI where sharing is real, then add platform-specific navigation and interaction. Apple supports a shared multiplatform target across iOS, iPadOS, and macOS, while recommending that developers verify framework/API availability and customize the experience per platform. A separate Mac target remains an option if app structure or platform APIs diverge. [Multiplatform target guidance](https://developer.apple.com/documentation/Xcode/configuring-a-multiplatform-app-target), [SwiftUI overview](https://developer.apple.com/documentation/technologyoverviews/swiftui).

Do not set minimum OS versions in this plan without confirming supported-user needs, current Xcode SDK availability, XKit dependencies, and API availability. Use current stable Xcode/Swift at project bootstrap; do not select a beta just because a folder has a new SDK name.

## UI structure

- iPhone: compact, focused navigation; optimize one-handed post reading and compose flow.
- iPad: use a sidebar/detail or split layout where it materially improves browsing; support multitasking and window size changes.
- macOS: support resizable windows, keyboard navigation/shortcuts, native menus, toolbars, and appropriate sidebar/search behavior.
- Shared components: post card/content rendering, profile summaries, loading/error/empty states, compose model, typography tokens, accessibility labels.
- Platform-specific components: navigation containers, menus/toolbars, keyboard affordances, presentation styles, window scenes.
- Build accessibility into components: VoiceOver labels, Dynamic Type, contrast, Reduce Motion/Transparency behavior, keyboard/focus support on Mac and iPad.

## Liquid Glass and HIG

Follow current Apple HIG and system conventions rather than adding a glass layer everywhere. Standard SwiftUI controls and navigation receive current system appearance automatically. Use custom Liquid Glass sparingly for important functional controls, and test it under accessibility display settings, different window/device sizes, and light/dark appearances. [Liquid Glass design overview](https://developer.apple.com/documentation/technologyoverviews/liquid-glass), [adoption guidance](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass), [toolbar HIG](https://developer.apple.com/design/human-interface-guidelines/toolbars).

Prioritize content legibility over decorative materials. Keep navigation, search, and actions consistent across platforms while adapting placement. Do not emulate X’s private app controls from dump class names; design a distinct native client.

## Swift version and API freshness

- Use the latest stable Xcode/Swift combination that can be installed and reproduced in CI when implementation starts.
- Adopt Swift 6 language mode and strict concurrency where the dependency/toolchain matrix allows; if staged, set a migration owner and target date. Apple notes Swift 6 strict checking finds data-race risks at compile time. [Swift 6 concurrency adoption](https://developer.apple.com/documentation/swift/adoptingswift6).
- Before adding any Apple API, inspect the current Apple documentation for platform availability and deprecation status; set the minimum OS only after the required features are known.
- Prefer Foundation `URLSession`, structured concurrency, Keychain/Security, and AuthenticationServices; avoid legacy callbacks or deprecated auth/browser APIs when supported replacements exist.
- Put availability checks at the platform adapter layer, not throughout API model code.

## Size/performance goals

“Smaller than the X app” is a goal to measure, not a promise. Keep the first release lean: no embedded web copy of the app, no unnecessary analytics SDK, no bundled X app assets, limited dependencies, and bounded caches. Track release archive size, installed size, launch time, feed memory, image-cache size, and network usage on real devices. Compare only like-for-like architectures and feature sets.
