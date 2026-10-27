# Agent handoff guide

## Shared instructions

This workspace is **planning and evidence-first**. Read `README.md` and the relevant plan before editing. Do not invent endpoint support, auth scopes, Apple API availability, build success, or X app behavior. Use official X and Apple sources first. Clearly label observation, inference, and unknown. Put citations/URLs beside claims and add checked date. The current X Developer Guidelines require official API use and prohibit scraping/browser automation; do not implement private X app endpoints.

Do not modify the existing X 12.33 dump, erase examples, add credentials, or place generated code in production modules until the project owner starts implementation. Keep reverse-engineering research distinct from official API implementation.

## Suggested parallel work packages

| Work package | Scope | Deliverable |
|---|---|---|
| Official API inventory | Read current X API docs/OpenAPI and Developer Guidelines; map posts/users/search/lists/bookmarks/media/DMs/Spaces/scopes/access/cost | Endpoint-level matrix with primary links and unknowns |
| X policy and content obligations | Verify current Developer Agreement/Guidelines for content display, attribution, caching/deletion, redistribution, and AI processing | Release requirements with source links and owner |
| Auth feasibility | Confirm current OAuth PKCE native-app configuration, redirect requirements, scopes, refresh/revoke/logout, and system auth session on Apple platforms | Auth flow note plus minimal non-production spike plan |
| Apple project/toolchain | Inspect local Xcode/Swift/SDK availability, target options, deployment range, CI runners, API availability | Reproducible toolchain/platform decision record |
| SDK architecture | Review package boundaries and public API ergonomics; compare official XDK/repositories and community Swift packages by provenance/license/maintenance | Architecture decision record; no code until authorized |
| X dump research | Inventory the 12.33 dump and version provenance; map specific desired app feature gaps to symbols with exact artifacts | Separate evidence ledger; no endpoint guessed from symbols |
| Privacy/security | Threat-model public-client OAuth, Keychain, account isolation, local cache, telemetry, retention, and distribution disclosures | Security review and actionable checklist |
| UI/HIG | Translate current Apple HIG/Liquid Glass guidance into phone/tablet/Mac navigation and accessibility requirements | Screen map/wireframes/spec, with Apple source links |

## Required evidence format

For each conclusion, include:

- Claim and status: `confirmed`, `inference`, or `unknown`.
- Primary source URL and checked date.
- Exact docs section/endpoint/symbol/file/line as applicable.
- Access scopes, account eligibility, price/rate implication if applicable.
- Test method/result, or explicitly say it has not been tested.
- Version/platform limits and unresolved questions.

## Stop conditions

Stop and report if a requested capability requires an undocumented endpoint, app credential extraction, bypassing access controls, or a policy/legal interpretation. Do not silently substitute a guessed route. Propose the nearest documented alternative and show the product gap.
