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

[CI run 34158262112](https://github.com/idvoretskyi/token-budget/actions/runs/34158262112)
at `abe383f` on 2026-09-07 passed all 77 tests on both Linux and macOS 26, built and
packaged the native release app, verified its ad-hoc signature, and uploaded the
artifact. No interactive real-Mac validation has been completed.

The shared informational-warning forecast policy, its additional test (78 total),
the five-second packaged-process check, and upload-artifact v5 update await the
next green CI run. See [CI evidence and limits](ci.md).

## Before Calling It Validated

- Verify the pending 78-test suite and packaged-process smoke check on CI. Process
  survival for five seconds is not an interactive UI test.
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
- Validate forecast presentation with confirmed coverage and informational notices,
  while keeping actual import problems, missing prices, and unknown warnings blocking.
- Documented distribution, architecture support, Developer ID signing, and
  notarization. A CI development ZIP is not a notarized release.

Billing integration, account credentials, telemetry, a hosted service, and enforced
provider spending caps are outside the current product scope.
