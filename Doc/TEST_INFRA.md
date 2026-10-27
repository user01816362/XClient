# E2E Test Infra: XClient

## Test Philosophy
- Opaque-box, requirement-driven derived strictly from `ORIGINAL_REQUEST.md` and `PROJECT.md`.
- No reliance on internal view implementation details; verifies multiplatform SPM compilation, Swift 6 strict concurrency, headless verification runner (`swift run XClientApp --verify`), model mock contracts, data flows, and CI integration.
- Methodology: Category-Partition (Tier 1) + Boundary Value Analysis (Tier 2) + Pairwise Combinatorial Interactions (Tier 3) + Real-World Workload Scenarios (Tier 4).

## Feature Inventory & Test Matrix
| # | Feature | Source (requirement) | Tier 1 (Coverage) | Tier 2 (Boundary) | Tier 3 (Pairwise) |
|---|---------|---------------------|:-----------------:|:-----------------:|:-----------------:|
| F1 | SPM Multiplatform Package & Toolchain | ORIGINAL_REQUEST §R1 | 5 | 5 | ✓ |
| F2 | Adaptive HIG Navigation Framework | ORIGINAL_REQUEST §R1 | 5 | 5 | ✓ |
| F3 | Liquid Glass Appearance & Design Tokens | ORIGINAL_REQUEST §R1 | 5 | 5 | ✓ |
| F4 | Reverse-Chronological Timeline & Polling | ORIGINAL_REQUEST §R2 | 5 | 5 | ✓ |
| F5 | Rich PostCard Component Hierarchy | ORIGINAL_REQUEST §R2 | 5 | 5 | ✓ |
| F6 | Media Presentation & Download Pipeline | ORIGINAL_REQUEST §R2 | 5 | 5 | ✓ |
| F7 | User Profile Surface & Subtab Views | ORIGINAL_REQUEST §R2 | 5 | 5 | ✓ |
| F8 | Modern Post Composer & Threading | ORIGINAL_REQUEST §R2 | 5 | 5 | ✓ |
| F9 | Settings Panel & Customization | ORIGINAL_REQUEST §R2 | 5 | 5 | ✓ |
| F10 | XKit SDK Integration & Mock Data Provider | ORIGINAL_REQUEST §R3 | 5 | 5 | ✓ |
| F11 | macOS Executable Runner (`swift run XClientApp`) | ORIGINAL_REQUEST §R4 | 5 | 5 | ✓ |
| F12 | CI/CD Workflow & Matrix Integration | ORIGINAL_REQUEST §R4 | 5 | 5 | ✓ |

## Test Architecture
- **E2E Test Runner**: Dedicated standalone test suite inside `XAPP/XClient/Tests/XClientTests/` and automated shell test runner script `scripts/run_e2e_tests.sh`.
- **Pass/Fail Semantics**: All test assertions must pass with exit code `0`. Non-zero exit indicates test failure.
- **Test Tiers**:
  - **Tier 1 (Feature Coverage)**: 60 tests (5 per feature F1–F12). Happy path isolation tests.
  - **Tier 2 (Boundary & Corner Cases)**: 60 tests (5 per feature F1–F12). Extremes, zero/empty data, nil handlers, unicode, max text, offline fallbacks.
  - **Tier 3 (Cross-Feature Combinations)**: 12 pairwise interaction tests (e.g. Settings theme toggle x Liquid Glass rendering; Polling actor x Timeline viewmodel; Composer draft persistence x Timeline post insertion; Media download x Cache size tracking; User profile lookup x Bookmark toggling).
  - **Tier 4 (Real-World Application Scenarios)**: 6 end-to-end user workflows (e.g., launch app in offline mode -> browse reverse-chronological feed -> pull-to-refresh -> inspect post card -> open image & save to downloads -> open author profile & view tabs -> open composer & draft multi-post thread -> adjust settings theme & clear cache).
  - **Total Required Test Count**: 138 test cases.

## Real-World Application Scenarios (Tier 4)
| # | Scenario | Features Exercised | Complexity |
|---|----------|--------------------|------------|
| 1 | Cold Start Offline Launch & Interactive Navigation | F1, F2, F3, F10, F11 | High |
| 2 | Reverse-Chronological Browsing, Polling & Refresh | F4, F5, F10 | High |
| 3 | Media Inspection, Download & Cache Management | F5, F6, F9 | High |
| 4 | User Profile Navigation & Subtab Filtering | F5, F7, F10 | Medium |
| 5 | Composer Thread Drafting, Character Ring & Persistence | F8, F4, F10 | High |
| 6 | Settings Customization, Appearance & Cache Purging | F3, F9, F11, F12 | Medium |

## Coverage Thresholds
- Tier 1: ≥5 per feature (60 total)
- Tier 2: ≥5 per feature (60 total)
- Tier 3: 12 cross-feature interactions
- Tier 4: 6 realistic application scenarios
- **Total Minimum**: 138 test cases
