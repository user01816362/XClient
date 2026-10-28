# Real session integration status

This document records the current implementation, not a claim of complete X API compatibility.

The sign-in screen loads X's web login in an isolated WebKit data store. An account is accepted only after the authenticated credentials endpoint returns an identity matching the supplied user ID, if present. Stored account sessions are migrated from UserDefaults to the device-only Keychain after a successful write. Provider sign-in, endpoint acceptance, migration and account switching still require testing on an iOS device.

Search and post-detail calls are protocol requirements so a service's concrete implementation is used. Home no longer presents unrelated search results as its timeline, and a failed post request no longer produces a fabricated success. Optimistic timeline actions roll back after failure; delete waits for the server. Undoing a repost remains unsupported.

The composer sends only a single text post. Media and thread publishing are unavailable and preserved drafts containing either cannot be submitted. A reply action cannot submit an unrelated top-level post. The Bookmarks screen is still a placeholder. Do not interpret these guards as complete support for media, replies, or threads.

The SDK's existing test suites are registered in SwiftPM and the CI workflow runs them. CI and live-device tests have not yet validated these changes. X web GraphQL identifiers, server policies, transaction signing, login providers, pagination and individual endpoint responses may change or reject a session; the app must surface these failures instead of substituting sample data. The X app dump alone does not establish that a third-party client has access to every X feature.

## X 12.38 native timeline capture

The supplied `/private/tmp/modrenloginnetwork2/network-export.json` contains successful native requests on `api.twitter.com`: two `HomeTimeline` POSTs with path ID `jJDcI5j8gO_X3Eh19_ClbA` and one `HomeLatestTimeline` POST with ID `LkMvMAM1Ui6nh71XRbjrJA`. All three have HTTP 200 and report response lengths over 300 KB. The export does not contain their response bodies. The JSON contains credentials; this report intentionally records no header values or account information.

The current client sends web-session requests to `x.com/i/api` using different, hard-coded web IDs and a locally generated transaction ID. The native capture does not establish that those native query IDs, request variables, authentication or response shapes work for a web-cookie session. The generated transaction ID is not verified against X's current web implementation. Therefore the reason the web Home timeline fails is not established by this capture and switching the client to the native IDs would be unverified.

Post detail now retains the authors and root-conversation entries returned by the existing parser, and rejects a response that lacks the requested post. The parser's model does not yet represent direct-reply relationships, so the app cannot identify complete nested threads. Posting replies is unavailable until the mutation contract is verified. Profile, timeline, and conversation UI and endpoint behavior require current authenticated captures with response bodies and device validation; do not report them as complete based on headers or class dumps alone.

## Settings and storage

Settings opens from the gear on the current profile and is no longer shown in primary navigation. Theme selection is observed by the app root. The settings screen no longer advertises the disconnected glass-intensity and timeline-polling controls or a sample post as live functionality. The cache control covers only `MediaDownloadManager`'s directory, not SwiftUI's `AsyncImage`/URLSession caches, Photos or other system caches. Clearing is refused while this manager has an active download and errors are surfaced; these behaviors still need CI and device testing.

Profile edit/follow and several empty profile/post menu actions were removed from the interface pending real implementations. This targeted cleanup is not a completed audit of every screen; other placeholder and unverified API paths remain.
