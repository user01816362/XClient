# XKit architecture

XKit is the Swift package in `sdks/XKit`. `XAPP/XClient` depends on it through a relative SwiftPM path. Both packages specify Swift tools 6.0 and strict-concurrency settings; successful compilation and runtime safety must be established by CI and testing.

## Existing targets

| Target | Responsibility |
| --- | --- |
| `XKitModels` | Post, user, pagination, error and rate-limit types. |
| `XKitTransport` | HTTP request/response types, URLSession transport and web request header/transaction helpers. |
| `XKitAuth` | OAuth 2 PKCE primitives, authorization URL/token helpers, and a callback-validating flow coordinator. |
| `XKitAPI` | Public v2 services and experimental X web-session/GraphQL services and parsing. |
| `XKit` | Umbrella client exposing the component services. |
| `XKitTesting` | Mock transport used by tests and the headless runner. |
| `XKitCLI` | Command-line verification harness. |

The SDK declares iOS 16 and macOS 13 minimums; XClient declares iOS 17 and macOS 14. XClient's `SessionManager`, rather than a separate XKit Keychain module, currently stores an encoded account collection in Keychain. The API/service layer also includes private web-session paths: this is not an official-API-only implementation. The OAuth coordinator is currently an SDK capability only; onboarding still uses WebKit cookies, and no app client ID or redirect URI is configured.

## Authentication and account boundaries

The application still opens X's login in an isolated WebKit store, then verifies the returned session. The separate XKit OAuth flow helper builds a PKCE request and validates callback origin, unique state and authorization code before token exchange, but the UI does not invoke it. Captured web sessions are stored in the device-only Keychain with migration logic. Login, switching, logout, migration and storage failure behavior still need real-device verification. No passwords, cookies, auth headers or private response content belong in logs or checked-in fixtures.

## Endpoint and parser limits

Web GraphQL IDs are hard-coded and the transaction ID generator has not been verified against the current X web client. Do not assume an X iOS dump or native OAuth capture proves that web-cookie requests can use the same IDs or request structure. `GraphQLTimelineParser` handles selected shapes; missing models, nested conversation relationships, pagination and media need evidence and tests. Keep mock responses and live observations clearly identified.

See [REAL_SESSION_INTEGRATION_STATUS.md](REAL_SESSION_INTEGRATION_STATUS.md) for current evidence and [TEST_INFRA.md](TEST_INFRA.md) for validation. The former architecture proposal for a separate account-keyed XKitKeychain module and an official-API-only production client was a design proposal, not the current implementation.
