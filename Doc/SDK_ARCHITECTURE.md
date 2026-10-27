# XKit SDK architecture

## Design target

XKit should feel like an idiomatic Swift package over documented X APIs. It should expose app-level operations and typed models, while keeping HTTP, OAuth tokens, JSON, pagination, rate limiting, and endpoint version details behind testable interfaces.

The XKit API contract is defined by the current X Developer documentation and OpenAPI file, not by Swiftcord, X app symbols, or guessed endpoint names.

## Proposed package layout

| Package/target | Responsibility | Dependencies / forbidden coupling |
|---|---|---|
| `XKitModels` | Public value types, identifiers, paging metadata, API error types, forward-compatible enum cases | Foundation only; no UI frameworks |
| `XKitTransport` | URLSession-based transport, request signing/authorization injection, cancellation, decoding, structured HTTP errors, rate-limit metadata, retry policy | Foundation; no app UI or token persistence |
| `XKitAuth` | OAuth 2.0 Authorization Code + PKCE protocol, scope types, token response/refresh/revocation operations as documented | Foundation plus injected platform callback/browser adapter; no embedded secret |
| `XKitKeychain` | Optional Apple-platform credential storage keyed by account identity | Security; separate from core so CLI/tests can inject memory storage |
| `XKitAPI` | Typed endpoint services such as Posts, Users, Bookmarks, Likes, Follows, Lists, Media, DMs, Spaces when verified | Depends on Models + Transport; endpoint docs linked from each service |
| `XKitTesting` | Mock transport, fixture loader, request assertions, deterministic clock/backoff helpers | Test-only or explicit development dependency |
| `XKit` | Convenient umbrella product re-exporting supported public modules | Keep this façade small and documented |

Avoid one target per endpoint at the start. Split modules only when real client needs, build times, or dependency boundaries justify it.

## Public API rules

- Use `async` functions and structured cancellation for network calls.
- Inject an `HTTPTransport` protocol and token provider rather than hard-coding global state.
- Keep endpoint path, HTTP method, query parameters, required OAuth scopes, access class, and official docs URL close to the typed endpoint implementation.
- Return a typed `APIResponse<Value>` containing data, pagination metadata, and safe rate-limit metadata when present.
- Model server errors without assuming every response is successful JSON. Preserve request identifiers and status codes, but redact authorization headers and sensitive bodies.
- Handle unknown enum values and newly added JSON keys without crashing.
- Make pagination lazy/explicit. Avoid silently fetching unbounded pages or media.
- Do not silently retry writes. Retry only safe/idempotent operations or requests with an explicit idempotency guarantee; otherwise surface the error.
- Centralize rate-limit parsing and backoff; do not hard-code rate numbers based on stale docs.
- Avoid embedding app-only bearer tokens or confidential credentials in distributable app binaries.

## Authentication and multiple accounts

For a native app, implement the documented OAuth 2.0 Authorization Code with PKCE flow. Treat iOS, iPadOS, and macOS clients as public clients: a client secret cannot be protected inside the app. Use a platform-appropriate system authentication session and registered redirect/callback. Request only scopes needed for enabled features.

Represent an account as an identity plus token reference; store access and refresh tokens in Keychain with an account-scoped key. Support add/switch/remove account without mixing caches or request authorization. Confirm X’s current refresh, revoke, and account-disconnect semantics before release. Never treat X app cookies or tokens recovered from a dump as XKit credentials.

## API evolution

- Pin endpoint behavior to a checked-in generated or manually verified OpenAPI snapshot, with source URL, retrieval date, and SHA-256.
- For each released API change, record the endpoint version, auth scope, required app permission/access, usage cost notes, changelog/source link, and test fixture provenance.
- Add integration tests for representative payloads; add compatibility tests for unknown fields/enum values.
- Deprecate XKit symbols only after the upstream API change is confirmed and migration guidance is written.
- Keep undocumented app endpoints in a separate research-only module/repository; they must not leak through public XKit exports.

## Sample call shape (illustrative, not implemented)

```swift
let client = XClient(
    transport: URLSessionTransport(),
    tokenProvider: keychainTokenProvider
)

let page = try await client.bookmarks.list(for: accountID, pagination: .firstPage)
```

This is a proposed shape, not a claim about a verified endpoint signature or access entitlement. Endpoint availability must be confirmed before implementation.

## Compatibility

- Build package targets on every supported Apple platform in CI.
- Set deployment targets only after Phase 0 confirms product support requirements and API availability.
- Keep Foundation-only modules portable to macOS and Linux where practical, but do not make Linux support a release requirement unless it benefits an actual consumer.
- Use the current stable Swift toolchain and adopt Swift 6 strict concurrency with checked `Sendable` boundaries. Record any temporary migration warning with an owner and removal issue.
