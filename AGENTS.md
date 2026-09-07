# Repository Guidance

## Product Boundaries

- Token Budget is a generic, open-source native macOS 26+ utility. Keep SwiftUI UI
  separate from portable Swift core and import logic.
- Runtime behavior must remain local: no network calls, telemetry, account login,
  credential discovery, or billing API integration.
- Estimate observed OpenCode and Codex CLI usage. Never describe an estimate as an
  invoice, verified balance, complete account usage, or enforced spending limit.
- Budgets use explicit source/provider/model selections, weekly or monthly
  periods, and a stored time zone. Initial prices are manual, dated profiles.
- Do not advertise incremental importing or real-Mac validation without evidence.

## Implementation

- Read `Package.swift` and `Sources/BudgetCore/Models.swift` before changing shared
  interfaces. Coordinate model changes with adapter and app owners.
- Keep edits small and use `apply_patch` for manual changes. Preserve work owned by
  other contributors or agents; honor the current task's file ownership.
- Source files are read-only inputs. Never modify a user's session history or
  source database. Unknown formats and missing prices need explicit uncertainty,
  not fabricated zero-cost or complete-coverage results.
- Keep token categories disjoint and money calculations decimal. Test boundary
  conditions, deduplication, malformed input, and time-zone transitions.
- Use synthetic fixtures only. Do not include personal paths, prompts, session
  identifiers, raw logs, credentials, or organization-specific examples.
- Import warnings must be static and public-safe, consistent with `ImportReport`.
  Do not interpolate records, identifiers, paths, or underlying error dumps.

## Verification

- Portable checks: `swift test` with Swift 6 and SQLite development headers plus
  `pkg-config` on Linux. The UI target is intentionally absent there.
- Native checks on macOS 26+: `swift test`,
  `swift build --product TokenBudget`, and `bash scripts/build-app.sh`.
- The packaging interface is `dist/TokenBudget.app`; do not claim a working bundle,
  signing, notarization, or interactive behavior from Linux results.
- CI must use read-only repository permissions, verified full action commit SHAs,
  no `pull_request_target`, and narrowly scoped, short-lived artifacts. Verify
  runner labels and installed Xcode paths in official runner documentation.
- Report what actually ran, failures, and remaining gaps. Do not commit or push
  unless the user explicitly asks.
