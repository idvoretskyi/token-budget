# Architecture

Token Budget targets a native SwiftUI menu bar experience on macOS 26+, backed by
portable Swift logic. This describes the MVP boundaries and shared models, not a
claim that every integration has been validated.

## Package Boundaries

| Target | Responsibility |
| --- | --- |
| `BudgetCore` | Usage and settings models, decimal pricing, budget-period logic, local state |
| `UsageAdapters` | Read-only OpenCode and Codex CLI imports and token normalization |
| `CSQLite` | System SQLite interface, not a bundled remote service |
| `TokenBudgetDiagnostics` | Local diagnostics executable; output must remain public-safe |
| `TokenBudgetApp` | macOS-only SwiftUI app and platform integrations |

The manifest conditionally excludes `TokenBudgetApp` on Linux. Portable tests
cannot validate AppKit/SwiftUI behavior or macOS permissions.

## Data Flow

```text
User-enabled local sources
  -> read-only adapters
  -> ImportReport (normalized events, static warnings, scan count)
  -> explicit source/provider/model selection
  -> dated price profiles + fixed-time-zone budget period
  -> estimated usage and uncertainty in the native UI
```

`UsageEvent` holds an ID, source, timestamp, provider, model, and `TokenCounts`.
The token categories are disjoint input, cache-read, cache-write, and output.
Adapters must resolve source-specific overlap before pricing; counting cache
tokens twice is not an acceptable approximation.

`UsageSelection` matches source, provider, and model exactly. `PriceProfile` uses
the same scope plus currency, `effectiveFrom`, decimal per-million rates, and
provenance. `BudgetConfiguration` stores amount, currency, weekly/monthly period,
time-zone ID, weekday, hour, and minute. `AppSettings` carries enabled sources,
selected paths, selections, prices, notification preference, and an optional
user-confirmed coverage start.

The current app stores `settings.json`, `scan-status.json`, and `usage.sqlite` in
its `TokenBudget` subdirectory of the user's Application Support directory. It
merges imported events into the local ledger, retains history when a source is
disabled or a scan fails, and coalesces refresh requests during an active scan.
While running, the app requests refreshes every 60 seconds; this is polling, not
file watching or incremental import.

`Ledger` isolates its SQLite connection in an actor and uses transactional upserts
keyed by source and event identity. A repeated identity replaces its entire
normalized payload; a failed batch rolls back. Entries absent from a later scan
are retained, not deleted. The database uses WAL, schema version 1, bound values,
and owner-only database-file permissions, and rejects newer storage versions.
Persistent notification keys share the ledger but are separate from usage rows.

`BudgetEngine` resolves calendar reset days forward with explicit skipped/repeated
time policies and prices half-open usage windows using decimal arithmetic. See
[pricing](pricing.md) for DST rules and the current warning-gated forecast limitation.

## Notifications

Portable `BudgetAlerts` decides whether an eligible scan crosses 80% or 100% of
the recorded estimate. It establishes silent baselines, rejects unknown warning
types, and generates stable local deduplication keys. macOS-only
`BudgetNotifications` handles opt-in permission, checks and records keys in the
ledger before delivery, and submits local `UserNotifications` requests. Configuration
revisions prevent stale scan results from issuing alerts for changed settings.

The OS payload contains generic threshold text and a random request ID, not local
deduplication keys or source/provider/model identifiers. Permission and delivery
failures do not trigger historical catch-up. This integration is implemented but
not interactively validated on a real Mac.

## Import Strategy

Treat refresh as a **full-rescan MVP**, not an incremental ingestion engine.
Repeated scans need stable identity and deduplication so the same observed usage
is not charged twice. The presence of SQLite or persisted event IDs does not prove
that imports resume from durable offsets.

Incremental cursors, file watching, rotation/truncation handling, and performance
at large history sizes remain separate work requiring evidence and tests. Source
formats may change, records may disappear, and files may be incomplete while
their producing tool writes them. Consult [compatibility](compatibility.md) for
adapter-specific evidence; do not infer support for every tool version.

## Trust and Uncertainty

Source inputs are read-only and untrusted. Keep raw records out of the core model,
UI warnings, diagnostics, tests, and issue reports. `ImportReport.warnings` is
explicitly limited to static, public-safe messages, without paths or identifiers.

Missing prices, unrecognized records, disabled sources, and incomplete history
must remain visible as uncertainty rather than silently implying complete spend.
The model's `coverageStart` records a user's assertion; it cannot independently
prove completeness. Local storage details and incremental behavior should be
documented from the implementation, not inferred from model types.
