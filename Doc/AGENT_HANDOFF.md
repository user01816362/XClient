# Agent handoff

Read [PROJECT.md](PROJECT.md), [REAL_SESSION_INTEGRATION_STATUS.md](REAL_SESSION_INTEGRATION_STATUS.md), and the code relevant to the task. Distinguish source inspection, captured native behavior, mock tests, CI results and device-confirmed behavior; none substitutes for another.

The local `.agents/teamwork/` files are historical agent dispatches, progress reports and handoffs. Their milestone and test claims describe earlier work, not the present state; preserve them as history and use the project documents above for current status.

The repository already implements experimental private web-session endpoints as well as public API services. Do not describe it as official-API-only or claim that X's native app dump proves these requests work. When changing an endpoint or login flow, preserve account isolation and record the exact evidence and known limitations. Never expose cookies, authorization headers, tokens or private content in logs or documentation.

Use GitHub Actions to validate builds for this workspace. Do not run local builds unless the user changes that instruction. CI operates on a committed remote revision, and this workflow can publish releases, so check the event and publication settings before running it. Preserve existing work in the shared working tree.

Settings is reached from the profile gear; its cache control covers only the app's downloaded-media cache. Replies, thread/media posting, undo repost and the Bookmarks screen are incomplete. Check the current source and status document instead of assuming old milestone plans represent shipped behavior.
