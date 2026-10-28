# Testing and release plan

> **Plan, not test results:** The current changes have not been built or tested. The existing workflow runs on GitHub Actions and includes SDK/client tests, mock smoke checks and an unsigned iOS archive; it does not currently implement every CI requirement listed below. No local build is requested. See [test infrastructure](TEST_INFRA.md).

## Test layers

### Unit tests

- OAuth state/PKCE generation and callback validation without real credentials.
- Request construction: methods, paths, query encoding, scopes, headers, redaction.
- JSON decoding for documented fixtures, missing/null fields, unknown keys/enums, API errors.
- Pagination boundaries, duplicate pages, cancellation, invalid next-page token.
- Rate-limit reset parsing, retry-after, backoff, no automatic duplicate write.
- Multi-account token selection and cache partitioning.

### Contract tests

- Keep redacted request/response fixtures tagged with source docs, API version/date, and endpoint acceptance records.
- Compare hand-written or generated models against the current official OpenAPI contract.
- Fail CI on unreviewed OpenAPI changes; generate a human-readable endpoint diff.
- Do not check in live access tokens or personally identifiable API payloads.

### Integration tests

- Explicitly opt in locally with a developer-created test app and test account.
- Test PKCE callback, login, refresh, logout/revocation, account switch, representative read and write operations, and error handling.
- Confirm billing/usage impact before repeating or scheduling tests.
- Keep credentials in local Keychain/environment outside tracked files; tests must skip with a clear message when credentials are absent.

### Platform tests

- Build and run on iPhone and iPad simulators/physical devices and a Mac destination.
- Exercise fresh install, login cancellation, expired/revoked token, offline state, rate limit, API outage, large text, VoiceOver, keyboard navigation, rotation/resizing, light/dark, Reduce Transparency/Motion.
- Verify deep links and OAuth callbacks on each supported OS.

## CI requirements

- Swift package build and test on all declared platforms supported by runners.
- Swift 6 strict concurrency diagnostics (or tracked migration exceptions).
- Formatting/linting and DocC generation if adopted.
- Dependency/license audit and secret scan.
- App build matrix using the pinned stable Xcode version; archive-size artifact.
- No network-backed integration test in default CI.

## Release gates

1. Every exposed endpoint has an API acceptance record and test coverage.
2. Current X developer terms/policies and endpoint access have been reviewed.
3. OAuth scopes are least-privilege; no client secret or test token is bundled.
4. Privacy disclosures match actual telemetry and data retention.
5. API errors, rate limits, pagination, and account disconnect are implemented.
6. Accessibility and platform-specific UI checks pass on iPhone, iPad, and Mac.
7. Dependencies and example-code licenses have been reviewed.
8. App Store/sideload/distribution requirements are checked for the intended distribution path.
9. App Store privacy details and privacy manifests accurately account for app and dependency behavior when App Store distribution is selected.
10. Release notes list verified features, known gaps, supported OS versions, API access requirements, and any usage-cost exposure.

## Reproducibility record

For every build/release, record Swift/Xcode version, SDK versions, source commit, dependency resolution, target deployment versions, API schema snapshot/hash, and test results. Re-run current X API and Apple documentation checks at release time.
