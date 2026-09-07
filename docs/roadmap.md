# Roadmap

This is a list of validation needs and possible follow-up work, not a release
schedule or a claim that features have shipped.

## Experimental MVP

- Native macOS 26+ menu bar UI with portable Swift core and read-only local adapters.
- Explicit source/provider/model scope and weekly/monthly, fixed-time-zone budgets.
- Manual dated prices, decimal estimates, and visible uncertainty.
- Full rescans as the baseline; no incremental-import performance promise.
- Local-only runtime without network requests, telemetry, or credentials.

## Before Calling It Validated

- Complete macOS 26+ test, build, packaging, and signature-verification runs.
- Verify the planned `dist/TokenBudget.app` output meets the CI packaging contract.
- Validate launch, menu bar behavior, settings persistence, accessibility, and
  notifications interactively on a real Mac. No such validation is recorded yet.
- Exercise permissions, unreadable files, concurrent source writes, repeat scans,
  and malformed input without exposing private data.
- Establish synthetic compatibility fixtures and document supported formats and
  unknown cases without claiming all upstream releases are supported.
- Test pricing effective dates, unknown prices, partial coverage, reset boundaries,
  and daylight-saving transitions.
- Verify storage lifecycle, data removal, and behavior with large histories.

## Possible Follow-Up

- Incremental imports with explicit cursor, deduplication, rotation, truncation,
  and recovery semantics, justified by profiling and regression tests.
- Broader source-format compatibility backed by synthetic fixtures.
- Improved local price-profile editing and provenance, without a runtime price feed.
- Opt-in threshold notifications with permission handling and deduplication;
  notifications are not implemented in the current app.
- Documented distribution, architecture support, Developer ID signing, and
  notarization. A CI development ZIP is not a notarized release.

Billing integration, account credentials, telemetry, a hosted service, and enforced
provider spending caps are outside the current product scope.
