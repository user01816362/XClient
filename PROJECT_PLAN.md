# Project plan

## Product definition

Create XKit, a reusable Swift SDK for documented X APIs, then use it in XClient: a native SwiftUI client for iPhone, iPad, and macOS. XKit is the reusable product; XClient is a first-party consumer/example of the SDK. The SDK must be usable independently of the app UI.

## Decisions already grounded in evidence

| Decision | Basis |
|---|---|
| Swift is a suitable language for a shared Apple-platform app and SDK | Apple documents SwiftUI multiplatform apps and shared targets for iOS, iPadOS, and macOS. |
| OAuth 2.0 PKCE is the first native login flow to investigate | X documents PKCE and identifies native apps as public OAuth clients. Never ship a client secret in a public app. |
| Build the first API contract from X API v2 | X describes v2 as recommended for new projects and v1.1 as legacy, while noting some endpoints remain in v1.1. |
| XKit is not an X app plugin system | X’s public API is for separate integrations/clients; the local 12.33 dump shows app internals, not a general third-party plugin contract. |
| UI should primarily use system controls | Apple’s current Liquid Glass guidance says standard components pick up platform appearance and discourages overusing custom glass. |

Source links are in [README](README.md), [API coverage](API_CAPABILITY_MATRIX.md), and [Apple platform UI](APPLE_PLATFORM_UI.md).

## Phases and exit gates

### Phase 0 — Repository/toolchain and policy inventory

- Inspect all files in `exmaple`, `sdks`, and `XAPP`; record commit, source, license, version, and hash where applicable.
- Verify installed Xcode, Swift compiler, simulator runtimes, signing/distribution route, and full SDK availability. The presence of `SDKSettings.plist` alone is insufficient.
- Read current X Developer Guidelines, Developer Terms, endpoint docs, OAuth docs, and pricing before making endpoint calls. X’s current guidelines say to use only the official API and prohibit scraping/browser automation; the released client must follow that requirement. Confirm current content display, attribution, retention/deletion, redistribution, and AI data rules as release requirements.
- Check all reference-project licenses. Do not reuse code until license compatibility is reviewed.
- Output: `research/` evidence notes and toolchain inventory.

**Exit:** install/select a complete Xcode toolchain, then compile a minimal Swift package/app for the intended targets; developer access and an approved X app are available; acceptable distribution/auth use case is documented.

### Phase 1 — Official API feasibility spike

- Register/configure a developer app under the project owner’s account; do not store credentials in the repository.
- Implement a tiny disposable Swift command-line or test harness for OAuth 2.0 PKCE using a public-client configuration, callback, token exchange, refresh, and revoke/logout behavior where documented.
- Validate a small set of representative user-authorized operations: current user/profile, read timeline/search as accessible, read/write one supported action (e.g. bookmark or post), and media upload if it is in MVP.
- Record required scopes, access approval, API cost/credit behavior, rate headers, pagination, failure semantics, and observed response fixtures with secrets and personal data removed.
- Compare each desired first-release feature to the live endpoint docs and developer-console access. The documented home timeline is reverse chronological and excludes algorithmic ranking; do not promise a For You equivalent from it.

**Exit:** one account can sign in and perform the MVP API operations end to end; all calls are supported by current official documentation; access/cost risks are acceptable. If not, narrow or stop before building the full UI.

### Phase 2 — XKit package foundation

- Add SwiftPM package targets described in [SDK architecture](SDK_ARCHITECTURE.md).
- Define stable typed requests/responses, transport injection, cancellation, rate-limit awareness, pagination, and structured errors.
- Add fixtures and deterministic tests. Adopt Swift 6 strict concurrency incrementally and resolve warnings intentionally.
- Generate DocC documentation and a minimal integration sample.

**Exit:** package builds for iOS, iPadOS, and macOS; transport tests run without network; live smoke tests run only when a developer supplies valid local credentials.

### Phase 3 — Native client MVP

- Implement sign-in/account management, home/timeline surface only where official endpoints allow, profile, post detail/thread, compose, and a short explicitly listed set of actions.
- Use SwiftUI with adaptive navigation: compact iPhone navigation, iPad sidebar/detail where appropriate, Mac window/sidebar/toolbar conventions.
- Use native system authentication UI and Keychain-backed token storage.
- Do not add unverified endpoints just to imitate the official app.

**Exit:** core journey passes on physical/simulator iPhone, iPad, and Mac; accessibility, offline/error states, rate-limit errors, privacy disclosures, and account revocation are reviewed.

### Phase 4 — Coverage expansion

- Add API domains individually (lists, bookmarks, media, DMs, Spaces, trends, notifications if supported), each with a documented endpoint/scope/access/cost row and tests.
- Review current X changelog/OpenAPI on a scheduled release cadence; propose changes via reviewed SDK updates.
- Update the class-dump evidence separately; never auto-generate runtime hooks or production endpoints from dump symbols. Dump discoveries cannot be used to bypass X’s official-API-only guidance.

### Phase 5 — Release hardening

- Audit secrets, privacy manifests/disclosures, permissions, accessibility, localization, network behavior, crash logs, API policy, licenses, app review/distribution, and platform availability.
- Re-run test matrix against minimum supported OS and latest stable OS/toolchain.
- Publish SDK and app versions with endpoint support matrix, migration notes, known gaps, and provenance.

## First implementation backlog

1. Add project inventory (actual toolchain, SDK, reference repo revisions/licenses, X dump hashes/version).
2. Confirm X API developer access and obtain no production secrets in source control.
3. Write an endpoint-level MVP contract sheet from X’s OpenAPI/docs, including OAuth scopes and pricing/access notes.
4. Prototype OAuth PKCE with a system authentication session; confirm callback works on iOS/iPadOS and macOS.
5. Validate one read and one write API flow with a test account.
6. Establish XKit package layout and Swift 6 concurrency migration policy.
7. Add endpoint fixtures, transport mocks, and CI build matrix.
8. Build UI only after steps 1–6 pass.

## Decisions to leave open until evidence exists

- Minimum deployment OS for each platform.
- Swift language mode and toolchain pin (use latest stable supported by CI, confirm in Phase 0).
- Whether to use one multiplatform app target or separate iOS/macOS targets after evaluating API availability and UI divergence.
- Whether direct messages, media upload, notifications, trends, Spaces, and search are in MVP.
- Whether a small backend is needed. Start client-only; only add a backend for a documented reason, and never put a confidential secret into a public client.
- Any use of undocumented X app endpoints. No production use is approved by this plan; the current X guidelines require official API access.
