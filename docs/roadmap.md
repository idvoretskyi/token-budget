# Roadmap

This is a list of validation needs and possible follow-up work, not a release
schedule or a claim that features have shipped.

## Experimental MVP

- Native macOS 26+ menu bar UI with portable Swift core and read-only local adapters.
- Explicit source/provider/model scope and weekly/monthly, fixed-time-zone budgets.
- Manual dated prices, decimal estimates, and visible uncertainty.
- Full rescans as the baseline; no incremental-import performance promise.
- Calendar reset policies for DST gaps/folds, transactional local usage upserts,
  and durable notification deduplication.
- Optional 80%/100% recorded-estimate alerts with permission handling, silent
  baselines, and generic payloads without private identifiers.
- Local-only runtime without network requests, telemetry, or credentials.

## Validation Snapshot

As reported on 2026-09-07, 76 portable tests passed locally and macOS CI compilation
passed. All macOS adapter tests in that run were skipped due to a path-symlink bug;
the fix needs a verified rerun with those tests actually executing. This is not a
passing native test suite or packaging result. Native packaging/signature checks
and interactive real-Mac validation are not confirmed.

## Before Calling It Validated

- Rerun macOS 26+ tests without unintended adapter skips, then confirm native
  product build, packaging, and signature-verification results.
- Verify the planned `dist/TokenBudget.app` output meets the CI packaging contract.
- Validate launch, menu bar behavior, settings persistence, accessibility, and
  notifications interactively on a real Mac. No such validation is recorded yet.
- Exercise permissions, unreadable files, concurrent source writes, repeat scans,
  and malformed input without exposing private data.
- Maintain the existing synthetic compatibility fixtures and documented format
  limits without claiming all upstream releases are supported.
- Run the existing pricing, ledger, calendar, and alert regressions across supported
  environments; portable results alone do not verify native integrations.
- Verify notification denial, re-enabling, baseline resets, persistence, and
  payload visibility without private identifiers on a real Mac.
- Verify storage lifecycle, data removal, and behavior with large histories.

## Possible Follow-Up

- Incremental imports with explicit cursor, deduplication, rotation, truncation,
  and recovery semantics, justified by profiling and regression tests.
- Broader source-format compatibility backed by synthetic fixtures.
- Improved local price-profile editing and provenance, without a runtime price feed.
- Review forecast warning policy without weakening uncertainty reporting. Currently
  every importer warning suppresses forecasts, including the coverage notice both
  adapters always emit, so real adapter imports effectively cannot show forecasts.
- Documented distribution, architecture support, Developer ID signing, and
  notarization. A CI development ZIP is not a notarized release.

Billing integration, account credentials, telemetry, a hosted service, and enforced
provider spending caps are outside the current product scope.
