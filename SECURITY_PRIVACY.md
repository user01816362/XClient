# Security and privacy plan

## Security goals

- Never request or handle an X password directly.
- Keep client secrets out of the app: iOS, iPadOS, and macOS distributed apps are public clients.
- Request least-privilege OAuth scopes and explain why each scope is needed.
- Keep credentials in Keychain; use account-specific keys and accessibility appropriate to the app’s behavior.
- Do not log access/refresh tokens, authorization headers, private message bodies, drafts, or full API response payloads.
- Provide clear account removal/logout and remove local credentials and account-scoped cached data when requested.
- Make account isolation explicit: every authenticated request, cache, and persisted item is associated with the correct account.

## Login plan

Use X’s documented OAuth 2.0 Authorization Code with PKCE for a registered native public client. Do not embed a client secret. Use Apple AuthenticationServices system web authentication (not a hard-coded desktop browser user agent and not a hand-built login WebView), configure the redirect URI with X, validate state and PKCE response values, and handle cancellation/errors. Apple documents `ASWebAuthenticationSession` as the system mechanism for third-party web authentication; it presents an OS-controlled confirmation/session and returns the callback to the initiating app. Confirm current Apple and X guidance during implementation. [Apple authentication session](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession), [X OAuth PKCE](https://docs.x.com/fundamentals/authentication/oauth-2-0/authorization-code).

Request only scopes the user has enabled features for. `offline.access` changes token lifetime/refresh behavior, so document its purpose and provide revocation/disconnect handling. Never assume a refresh token means the account can never log out or be revoked.

## Data handling defaults

- Analytics: none by default. If later added, make it opt-in where feasible, document events and recipients, and never include message content, tokens, or sensitive identifiers.
- Local state: persist only what supports expected UX; distinguish ephemeral image/data caches from user-created drafts/settings.
- Remote services: start without an XProject backend. A backend would add another party handling credentials or data and needs a concrete feature justification and separate threat review.
- Error reporting: scrub URL query secrets, auth headers, user identifiers where possible, and response bodies by default.
- Images/media: use bounded cache sizes, purge policies, and documented cache behavior.
- X content: implement a documented purge/re-fetch approach that meets the current X deletion and display rules. The current guidelines describe deletion within 24 hours for specified removal requests/events and require attribution/display compliance; verify exactly how those obligations apply to an on-device client before shipping.
- Network: TLS validation stays enabled; no certificate bypass or plaintext fallback.
- Diagnostics: export only sanitized diagnostics with user consent.
- Apple privacy disclosures: if App Store distribution is chosen, keep App Store Connect privacy answers accurate for the app and all third-party SDKs. Inspect dependencies for data collection, tracking domains, and required-reason APIs; include valid `PrivacyInfo.xcprivacy` manifests where Apple requires them. No-analytics-by-default does not waive manifest/disclosure requirements. [Apple privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files), [App Store privacy disclosures](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/).

## Threat review checklist

- OAuth redirect interception, invalid state, replay, callback spoofing.
- Access token/refresh token exposure through logs, crash reports, clipboard, backups, screenshots, or shared containers.
- Cross-account cache leakage when switching accounts.
- Malformed or oversized API responses, pagination loops, decompression/resource exhaustion.
- Retry loops that duplicate writes or exhaust paid API credits.
- Deep-link input validation and open redirects.
- Web authentication session cancellation and platform callback handling.
- Untrusted community packages, generated code, and dump-derived endpoints.
- API data retention/deletion rules and current X developer policies.

## AI and extensibility boundary

AI assistance may help developers generate a **reviewable XKit feature proposal or source patch** from documented APIs and this repository’s public interfaces. Do not execute arbitrary generated Swift or downloaded native plugin code inside the app. AI must not receive tokens, private content, dump-derived secrets, or account session data. Do not use X content to train or fine-tune a model; review current X policy before sending any X content to an external AI service for processing. X’s current guidelines state that AI-generated replies/posts require prior approval from X. All generated code requires human review, tests, policy check, and signed release packaging outside the running client. [X Developer Guidelines](https://docs.x.com/developer-guidelines).
