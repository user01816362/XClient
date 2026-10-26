# X API capability and gap matrix

**Evidence checked:** 2026-10-15. This is a starting map, not a parity claim. Recheck the live X docs, OpenAPI, developer console, OAuth permissions, and pricing before implementing any row.

## How to read this matrix

- **Documented family** means the official docs describe the capability family. It does not prove that our app is approved, the endpoint is enabled for our app, or that every first-party app feature is exposed.
- **Verified end to end** means tested with our developer app and test account on the current API contract. No feature is marked that way yet.
- **Private/unverified** means the current official docs reviewed here do not establish that the native app exposes the behavior to external clients. Do not implement via guessed/private endpoints.

X’s own overview documents reading/publishing posts, user management, analytics, DMs, lists, and Spaces, and calls v2 recommended for new work while noting some specialized capabilities remain in v1.1. [About X API](https://docs.x.com/x-api/getting-started/about-x-api).

## Initial capability map

| Feature area | Official-doc status | Evidence / remaining verification |
|---|---|---|
| Read/look up posts and conversation threads | Documented family | Confirm exact endpoints, query limits, field/expansion requirements, access tier, and per-user data access. |
| Home / user timelines | Documented family | Current documented home endpoint is reverse chronological, limited to the most recent 3,200 posts or 7 days, and excludes algorithmic ranking. It does not establish For You feed parity. [Timelines docs](https://docs.x.com/x-api/posts/timelines/introduction). |
| Search and streams | Documented family | Confirm account entitlement, historical window, billing, rate limits, and streaming behavior before UI promises. |
| Create posts, replies, threads; delete posts | Documented family | Confirm write scope, media flow, allowed post options, and app permission. |
| User/profile lookup | Documented family | Confirm protected-account authorization scopes and field availability. |
| Follow/unfollow, block/unblock, mute/unmute | Documented family / scopes enumerated in OAuth docs | Verify endpoint-specific scopes, write effects, and current access. |
| Likes | OAuth docs list read/write scopes | Confirm endpoint coverage and access for our developer app. |
| Bookmarks | Explicit read/add/remove endpoints documented | Requires approved developer app and user authorization; verify folder endpoints and scopes. [Bookmarks docs](https://docs.x.com/x-api/posts/bookmarks/introduction). |
| Lists | Documented family | Confirm membership/follower operations and endpoint limits. |
| Media upload | OAuth docs include `media.write`; X overview notes some upload endpoints are still v1.1 | Map upload chunks/media types and legacy status; do not assume v2-only. |
| Direct Messages | Documented family and `dm.read` / `dm.write` OAuth scopes | Verify product access, current endpoints, cost, media/attachments, and policy before MVP. |
| Spaces | Documented family and `space.read` OAuth scope | Verify exactly which Space interactions are supported. |
| Trends | Documented resource family | Verify region/country, access requirements, update behavior, and cost. |
| API content display and local cache | Subject to X Developer Guidelines | Confirm display attribution/formatting and deletion requirements; current guidelines describe 24-hour deletion deadlines for specified events. Do not promise indefinite offline retention until the rules are reviewed for the exact use case. [Developer Guidelines](https://docs.x.com/developer-guidelines). |
| Push notifications | Not established by reviewed docs as an app-client feature | Investigate only through current official docs; do not promise equivalent first-party push. |
| Communities, Community Notes, News, personalized trends | Official docs list endpoint/resource areas | Verify exact operations, account entitlements, and behavior. Resource/category existence does not prove first-party app parity. [API docs index](https://docs.x.com/x-api/llms.txt). |
| Circles, premium/subscriber-only features, live video, full recommendations | Not established as complete public client API in the reviewed sources | Search current API docs/OpenAPI and developer access; otherwise record as a gap, not infer from app dump. |
| X app UI/plugin hooks | Not an API feature | X 12.33 dump has internal home navigation title/button plugin protocols; they do not define a public third-party app SDK or general plugin host. |

## Current auth facts

X’s OAuth PKCE guide describes native apps as public clients, granular scopes, access tokens defaulting to a two-hour lifetime unless `offline.access` is included, and refresh token issuance when that scope is included. This is sufficient to prototype login, but token refresh/revoke, multi-account storage, redirect registration, and live endpoint permissions must be tested. [OAuth PKCE documentation](https://docs.x.com/fundamentals/authentication/oauth-2-0/authorization-code).

## Official SDK/repository discovery

X’s docs index currently lists official Python and TypeScript XDKs. Its tools page lists Swift libraries Twift and TwitterAPIKit as **community libraries not maintained by X**. This makes an in-house XKit feasible, but requires an independent contract/test and maintenance plan. Treat this as a dated observation, not a permanent fact. Recheck the X docs index, official GitHub organization, and API changelog when implementation begins. [X docs index](https://docs.x.com/llms.txt), [X tools and libraries](https://docs.x.com/tools-and-libraries), [X API changelog](https://docs.x.com/changelog).

## Official API and policy gate

X’s current Developer Guidelines explicitly ask whether an app uses only the official API and say scraping/browser automation is prohibited. XKit and XClient therefore use documented official API calls only. Static app analysis may help describe product gaps, but cannot be used to fill those gaps with scraping or unapproved private calls. Review the current [Developer Guidelines](https://docs.x.com/developer-guidelines) and linked Developer Agreement before implementation and each release.

Community GitHub clients may help locate endpoint examples, but they are not evidence that an endpoint is official, supported, permitted, or current. Record repository owner, last commit, license, tested API date, authentication method, and policy fit before using them.

## Endpoint acceptance record (required for each feature)

```text
Feature:
Official docs URL:
API version / method / path:
Docs last checked (UTC):
X OpenAPI path or schema reference:
Required OAuth scopes:
Developer-app access/approval confirmed:
Pricing / usage implications checked:
Request/response fixture (redacted) location:
Read/write behavior tested on account we control:
Rate-limit and retry behavior tested:
Platform-specific constraints:
Known gaps / policy questions:
Decision: ship | defer | research-only | reject
Reviewer and date:
```
