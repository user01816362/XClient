# Test infrastructure

## What exists

- XClient tests are under `XAPP/XClient/Tests/XClientTests/`. They cover navigation, models, mock services, views, settings and selected regressions. They are predominantly unit or mock tests, not end-to-end X tests.
- XKit tests are under `sdks/XKit/Tests/`. Its package manifest registers API, authentication and transport test targets.
- `XClientApp --verify` and `XKitCLI test-all` are headless checks; their use of mocks does not validate a live account or endpoint.
- `.github/workflows/build.yml` runs `swift test` for XKit and XClient, the CLI/headless checks, SwiftPM builds and an unsigned generic iOS archive, then packages artifacts.

## Current verification state

The current working-tree changes have not been built or tested. The user requested no local builds; use GitHub Actions for a committed revision. The last successful remote run, if any, must be matched to its commit before using it as evidence. Check the workflow's release configuration before triggering it because some events publish releases.

A passing mock test or archive does not establish that X's login, private GraphQL contracts, transaction IDs, rate limits, account switching, media saves or device UI work. The former tier counts and E2E completeness claims in this document were not verified and have been removed.

## Required live checks

On a controlled account and iOS device, test sign-in/cancellation, account switching and logout, Home and pagination, post and profile loads, allowed actions, failure feedback, theme changes, cache clearing and media export. Keep tokens, cookies, prompts, post content and unredacted network captures out of repository artifacts. Document the exact build and outcomes; see [REAL_SESSION_INTEGRATION_STATUS.md](REAL_SESSION_INTEGRATION_STATUS.md) and [TESTING_RELEASE_PLAN.md](TESTING_RELEASE_PLAN.md).
