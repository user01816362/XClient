# X app dump and network research

`XAPP/X_12.38_dump/` and `XAPP/Payload/` are local research inputs for the supplied X version. Check their provenance and hashes before relying on them. Class names, method signatures and imported symbols establish only static properties of that binary; they do not prove a service is callable by XClient, that its request is authorized, or that its server response matches a parser.

The supplied timeline capture contains native X 12.38 Home and Following requests, but not their response bodies. [REAL_SESSION_INTEGRATION_STATUS.md](REAL_SESSION_INTEGRATION_STATUS.md) records the observable paths and limitations. The capture contains account credentials and must not be committed or reproduced in documentation or logs.

For every new finding, record the app/build, artifact and tool, exact sanitized observation, inference, alternative explanations, and whether it was tested at runtime. Compare native OAuth, web cookies, request paths, method, variables, pagination and response shapes before deciding that evidence applies to another client. Keep version-specific observations separate; don't infer compatibility across X releases from a matching class name.

The repository already includes experimental private web-session endpoints. Their presence is an implementation fact, not evidence of support, stability or permission. Review current X developer terms and applicable distribution requirements before release; consult current authoritative sources rather than treating the historical 2026-10-15 research as current. Never commit secrets or unredacted captures and do not claim end-to-end success without a controlled test.
