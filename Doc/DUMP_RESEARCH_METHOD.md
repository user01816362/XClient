# X app dump research method

## Purpose and limits

The X 12.33 dump at `XAPP/X_12.33_dump/` can help researchers document symbols, class/module organization, app navigation seams, and possible product gaps. It is a static snapshot of one binary. It cannot prove runtime behavior, endpoint authorization, server responses, long-term stability, or permission to reproduce a behavior in a separate client.

The dump is useful only as a **separate product-gap research input**, not as the XKit production contract. X’s current Developer Guidelines say apps must use the official API and prohibit scraping/browser automation. XKit/XClient production behavior must therefore come from documented official APIs and verified calls through our own approved developer app. Do not use private app endpoints to close a gap unless X explicitly authorizes that use and the project owner obtains policy/legal review; no such authorization is assumed here. [X Developer Guidelines](https://docs.x.com/developer-guidelines).

## Repository evidence inventory

The provided dump README identifies a full X 12.33 Twitter binary dump, generated 2026-10-11, with class-dump, Swift-dump, framework manifest, symbols, strings, Mach-O metadata, targeted output, and integrity hashes. The original source paths in that README point to an XEnhancer workspace, so those paths may not exist in this XProject copy. Treat the README as provenance supplied with the dump; independently verify the local files and hashes before relying on it.

One concrete symbol-level finding previously observed in this dump: `HomeNavigationBarTitleViewPlugin` and `HomeNavigationBarButtonItemPlugin` protocols are present, along with title/button plugin arrays in the home container factory. This confirms internal first-party UI extension seams in that binary snapshot. It does **not** show a third-party plugin registry or validate compatibility across releases.

## Evidence protocol

For every reverse-engineering observation, record:

1. Exact binary/app version, build, source provenance, hash, and analysis tool/version.
2. Artifact path and exact line, class, selector, symbol, address, string, or dataflow reference.
3. Observation stated literally (for example: “selector string exists in binary”).
4. Interpretation clearly labeled as inference, with alternative explanations.
5. Runtime confirmation steps and results, if any, on a test device/account we control.
6. Whether an equivalent capability exists in current official API documentation.
7. Compatibility scope: exact build only until verified on another version.
8. Security/privacy/policy questions and release decision.

Do not turn a string match, class name, dead code path, or method signature into a claim that a feature is callable or supported.

## Research safeguards

- Do not collect, export, or reuse real user passwords, session cookies, OAuth tokens, private messages, or other account secrets from the app or device.
- Do not put secrets, personal data, or unredacted traffic captures in this repository or agent prompts.
- Do not bypass authentication, access controls, or server-side authorization.
- Do not call internal app endpoints from XKit/XClient. Keep static observations separated from production code. Any future proposal involving undocumented endpoints is blocked until explicit X authorization and policy/legal review; the default decision is reject.
- Prefer official API endpoints, developer tooling, redacted fixtures, and test accounts.
- An endpoint discovered in analysis is not eligible for production merely because it works. The production client remains official-API-only under the current X guidelines. Absence of a restriction in a dump is not evidence of permission.
- Never auto-generate production endpoint code, hooks, plugins, or credentials from the dump.

## Version-diff workflow

When adding a new X app dump:

1. Keep immutable per-version inputs; never overwrite a prior dump.
2. Verify file hashes and collection provenance.
3. Generate normalized symbol/class/module inventories with tool versions captured.
4. Diff only like-for-like artifacts; account for renames, compiler changes, dead stripping, and tool output differences.
5. Prioritize diffs tied to an actual client feature gap.
6. Cross-check candidate behavior against current official API docs and test behavior only in an authorized, controlled setup.
7. Update `API_CAPABILITY_MATRIX.md` only when the change is backed by authoritative API documentation and/or verified permitted behavior. Keep internal app findings in this research file.

## Known limits of current input

- Only X 12.33 is identified in this workspace. Do not infer that it matches a current App Store build.
- Static dump symbols are not a complete model of server-side product behavior.
- No current X API account credentials, approval, or live API test results were provided.
- API behavior, entitlements, pricing, and policies change independently of the app binary.
