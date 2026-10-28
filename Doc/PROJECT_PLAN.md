# Project plan

The original official-API-first planning document predates the implemented web-session prototype. This plan describes the remaining work in the present tree; it is not a claim that all earlier milestones were completed.

1. **Validate the current revision.** Run the GitHub Actions workflow on the intended committed revision, without local builds. Resolve compile and test failures and verify that publication settings match the intended run.
2. **Verify session handling.** Test X login, provider behavior, authenticated identity, migration, account switching, logout and Keychain failures on iOS without recording secrets.
3. **Investigate real Home requests.** Compare a current controlled web-session capture and sanitized response fixtures with XKit's request IDs, signing and parser. Native X 12.38 timeline requests alone do not establish a working web request.
4. **Close core reading gaps.** Verify profile, post detail, conversation relationships, media and pagination using real responses. Correct error states and remove any remaining fake or misleading production UI.
5. **Add writes individually.** Confirm endpoint contracts and cancellation/error behavior before exposing replies, threads, attachments, follow/edit profile, bookmark listing and undo repost. Do not invent successful results or retry writes blindly.
6. **Finish UI and storage.** Test profile-based Settings, light/dark appearance, accessibility, cache boundaries and media export on supported devices.
7. **Release review.** Verify X endpoint access, privacy, account isolation, error handling, app packaging and any distribution requirements; publish only the capabilities actually tested.

The detailed current status and evidence are in [REAL_SESSION_INTEGRATION_STATUS.md](REAL_SESSION_INTEGRATION_STATUS.md). This plan does not promise compatibility with every X feature.
