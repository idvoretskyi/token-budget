# Usage Adapter Compatibility

Research date: 2026-09-07. Evidence is public, pinned released source, not user
logs. Tests construct synthetic JSON in Swift strings and temporary SQLite
databases. No downloaded user fixtures, installs, or source-data writes are used.

## Verified Releases

| Source | Released tag | Published | Resolved commit |
| --- | --- | --- | --- |
| OpenCode | `v1.18.29` | 2026-09-04 | `16747470f976aca3d362ad730bcd3fe82ecc2c9a` |
| Codex CLI | `rust-v0.153.4` | 2026-09-04 | `3d2ee51ca2d5db578f328aa75e20aa22c0197c9a` |

Verified with GitHub release and git-ref APIs. Codex's annotated tag object is
`042fb41b7c813ac7999105e886b2b7aa715b5081`, resolving to the commit above.
Release pages: [OpenCode](https://github.com/anomalyco/opencode/releases/tag/v1.18.29),
[Codex](https://github.com/openai/codex/releases/tag/rust-v0.153.4).

Version gates are intentionally exact: OpenCode `session.version == "1.18.29"`,
Codex `session_meta.payload.cli_version == "0.153.4"`. Structurally similar older,
newer, or missing-version records are skipped with a static warning. These are
creation-version metadata, not per-request provenance or cryptographic proof of
the writer version. Mixed-version sessions require caution; no full compatibility
range is claimed.

## OpenCode

Public API: `OpenCodeImporter.scan(path: String) throws -> ImportReport`.
Supply the SQLite file or a directory containing `opencode.db`. There is no
automatic home-directory discovery and no legacy JSON-storage fallback.

Pinned evidence:

- [Tables](https://github.com/anomalyco/opencode/blob/16747470f976aca3d362ad730bcd3fe82ecc2c9a/packages/core/src/session/sql.ts): `part(id,message_id,session_id,time_created,data)`, `message(id,session_id,time_created,data)`, `session(id,version,time_created)`.
- [V1 schema](https://github.com/anomalyco/opencode/blob/16747470f976aca3d362ad730bcd3fe82ecc2c9a/packages/schema/src/v1/session.ts): `step-finish.tokens` and assistant `providerID` / `modelID`.
- [Processor](https://github.com/anomalyco/opencode/blob/16747470f976aca3d362ad730bcd3fe82ecc2c9a/packages/opencode/src/session/processor.ts): each `step-finish` persists usage; message cost is incremented while message tokens are assigned the current step's tokens. Adding message or session totals would double count and message-only tokens could miss steps.
- [Normalization and fork implementation](https://github.com/anomalyco/opencode/blob/16747470f976aca3d362ad730bcd3fe82ecc2c9a/packages/opencode/src/session/session.ts#L338-L405): input already excludes cache reads/writes; output excludes reasoning. Adapter output is `output + reasoning`, with checked addition. Cache counts remain separate; upstream monetary cost is not imported.
- [Database](https://github.com/anomalyco/opencode/blob/16747470f976aca3d362ad730bcd3fe82ecc2c9a/packages/core/src/database/database.ts) and [timestamps](https://github.com/anomalyco/opencode/blob/16747470f976aca3d362ad730bcd3fe82ecc2c9a/packages/core/src/database/schema.sql.ts): WAL, `opencode.db`, millisecond creation timestamps.

Only canonical V1 `step-finish` parts are imported, using part creation time and
the joined assistant's model/provider. No fallback to message costs or newer
`session_message` data. Unknown databases fail visibly. An empty result warns;
it does not certify zero usage. Historical `v1.2.15` was also inspected and is
deliberately unsupported: its reasoning/output normalization differs.

OpenCode forks copy message creation times into newly created sessions while
assigning new message/part IDs, without reliable fork-parent metadata. The
adapter skips steps whose original message predates the session, warning about
fork ambiguity. This also conservatively skips imported/backdated messages.
Same-millisecond forks, clock anomalies, restored/imported IDs and histories
cannot be proved distinct from usage solely from these tables. Ledger dedup by
stable IDs does not solve forks that have new upstream IDs.

SQLite opens with `SQLITE_OPEN_READONLY`, not `immutable=1`, and uses a read
transaction, query-only mode, a 1-second busy timeout, and no migrations,
checkpoints or journal-mode changes. SQLite sees committed live WAL data. A
read-only WAL connection may require existing readable WAL/SHM files or SQLite's
ability to create its coordination sidecar; inaccessible state fails visibly,
never falls back to reading a stale main-database copy. Tests hold a writer open
and assert that main DB and WAL bytes are unchanged by scanning.

## Codex CLI

Public API: `CodexImporter.scan(path: String) throws -> ImportReport`.
Supply a plain `.jsonl` rollout file or a directory recursively containing them
(for example `sessions`, `archived_sessions`, or a deliberately selected parent).
Compressed archives, SQLite state, history.jsonl, paginated rollouts and inherited
subagent/fork histories are not supported. Missing source metadata is not guessed
from filenames, current configuration, environment variables, or model names.

Pinned evidence:

- [Wire envelope](https://github.com/openai/codex/blob/3d2ee51ca2d5db578f328aa75e20aa22c0197c9a/codex-rs/history/src/rollout_payload.rs): `type`, `payload`; [RolloutLine](https://github.com/openai/codex/blob/3d2ee51ca2d5db578f328aa75e20aa22c0197c9a/codex-rs/history/src/lib.rs) adds `timestamp`.
- [Protocol](https://github.com/openai/codex/blob/3d2ee51ca2d5db578f328aa75e20aa22c0197c9a/codex-rs/protocol/src/protocol.rs#L2215-L2321): `TokenUsage`, `TokenUsageInfo`, `append_last_usage`, `TokenCountEvent`; cumulative totals plus last-request usage, not independently billable repeated snapshots.
- [Session and turn metadata](https://github.com/openai/codex/blob/3d2ee51ca2d5db578f328aa75e20aa22c0197c9a/codex-rs/protocol/src/protocol.rs#L3031-L3230): session `id`, `cli_version`, `model_provider`; turn-context `model`; explicit inherited-history fields.
- [Recorder](https://github.com/openai/codex/blob/3d2ee51ca2d5db578f328aa75e20aa22c0197c9a/codex-rs/rollout/src/recorder.rs): JSONL persistence, first metadata identifies the rollout, later metadata can be copied fork history.
- [Persistence policy](https://github.com/openai/codex/blob/3d2ee51ca2d5db578f328aa75e20aa22c0197c9a/codex-rs/rollout/src/policy.rs): `TokenCount` and turn metadata persist; model-reroute events are normally transient.

Reads `event_msg.payload.type == "token_count"`, with `info.total_token_usage`
and `info.last_token_usage`. `info: null` is a rate-limit-only notification.
Input includes cached input, so disjoint input is `input_tokens -
cached_input_tokens`. Reasoning is an output subset and is not added again.
All required counters must be nonnegative Int64 integers, cache/reasoning subsets
must fit, and `total_tokens` must equal input plus output without overflow.
Optional absent `cache_write_input_tokens` defaults to zero as in the pinned
protocol. Nonzero cache-write usage is conservatively unsupported, not guessed
or silently charged as uncached input.

The first nonblank record must be valid, supported session metadata. A malformed,
oversized, unsupported, or absent initial header stops the file; a later copied
parent's metadata is never adopted as its identity. Leading blank lines are allowed.
Snapshots are processed in physical line order, not sorted by timestamps.
Identical cumulative snapshots emit nothing. A first snapshot is charged only
when total equals last usage and the stream prefix was intact. Otherwise it is
only a baseline, with a warning. Later deltas must be componentwise monotonic
and match last usage. Resets, divergent deltas, malformed or oversized records,
and compaction invalidate or re-establish the baseline without charging the
ambiguous transition. Missing model/provider or invalid timestamps omit that
delta while advancing accounting state so it cannot be charged to a later turn.

Fork metadata, inherited parent/subagent history, paginated histories and a
second session metadata record are skipped. Rollback stops subsequent import;
already observed pre-rollback usage remains spent. Compaction may cause an
undercount on the next snapshot. Model attribution uses the most recent turn
context; if an explicit reroute is present, model attribution is cleared until
new context. **The normal persisted protocol does not retain reroutes**, so the
configured model is not proof of the actual billed model. Mid-turn routing,
provider changes across resume, missing snapshots and aggregate-only histories
remain gaps. Token logs are not authoritative billing receipts.

## Bounds and Reconciliation

There is no window filter in either adapter. Every scan starts from the beginning
of selected sources, including pre-budget-window snapshots. The caller must
filter returned event timestamps only after normalization. This avoids charging
an entire lifetime cumulative total to the first snapshot inside a budget window.

Explicit MVP limits per scan:

- Codex: 10,000 discovered filesystem entries, 1,000,000 physical complete lines,
  100,000 emitted events, 256 MiB per file, 1 GiB total bytes.
- Streaming: 64 KiB chunks, 1 MiB maximum line buffer. Oversized lines are
  discarded through newline and invalidate attribution/baseline. A trailing
  unterminated record is deferred, even if it happens to parse as JSON. Reads
  freeze the file extent at open; appended bytes wait for the next scan.
- OpenCode: 250,000 part rows, 100,000 events, 1 MiB JSON metadata rows, SQLite
  8 MiB maximum value length, 1-second lock wait. Oversized or corrupt database
  values can cause the scan to fail rather than return partial accounting.
- Identifiers/model/provider metadata: nonempty, at most 256 UTF-8 bytes, no
  control characters. Int64 conversions, subsets and relevant sums are checked.
  SQLite text columns are decoded over their full byte length as strict UTF-8;
  embedded NUL bytes and invalid UTF-8 are rejected, not truncated or repaired.

Reaching limits produces static incomplete-coverage warnings; this is not a
hard real-time or constant-memory service. Results retain bounded events in
memory. SQLite query work also depends on source indexes and database size.
No persistent offsets or high-water marks are kept. Large histories may require
narrower explicit source selection; incremental reconciliation is future work.

Stable event IDs use source session/part IDs for OpenCode and source session ID
plus physical line byte offset for Codex. They are unchanged across repeated
scans and file moves into archives. The ledger owns deduplication across scans
and copies. Rewriting/truncating a rollout in place, reusing an upstream session
ID for different histories, or restoring conflicting copies can invalidate this
identity assumption. Such operations are not supported as an exactly-once
accounting workflow.

## Privacy and Diagnostics

No adapter writes source records, persists prompts/content, logs records, performs
network requests, or exposes paths in its errors/warnings. SQLite projects only
accounting metadata. JSONL records necessarily pass transiently through a bounded
buffer/JSON parser; unrelated content is discarded and never placed in events.
Events contain only contract accounting metadata; those IDs/model/provider
strings should still be treated as private by callers.

Symlink files, directories, ancestors and SQLite sidecars are rejected/skipped.
Existing WAL, SHM and rollback-journal sidecars must be regular files before
SQLite opens; directories, FIFOs and devices are rejected. Only a not-found
sidecar lookup is treated as absent; other lookup errors reject the scan.
Directory traversal errors warn; direct missing/unreadable sources throw static
errors. Checks are best-effort for a local trusted filesystem, not protection
against an adversary racing filesystem replacement between checking and opening.
Nonregular sources are not opened. Empty/no-supported sources are visible.

`token-budget-diagnostics opencode PATH` and `token-budget-diagnostics codex PATH`
emit only scanned-record/event/warning counts and static warnings. They do not
print tokens grouped by provider, event IDs, model names, raw errors, arguments,
or paths. Exit 2 means invalid invocation; exit 1 means scan failure; exit 0 can
still include incomplete-coverage warnings. Warnings are deduplicated static
categories, not per-record error counts. `scannedRecords` counts visited part rows
or physical complete JSONL lines, including irrelevant/invalid records.

All adapters are synchronous, have no shared mutable state, and are suitable for
calling off the UI actor under Swift 6. Tests use XCTest and synthetic temporary
data only. The review fixes were checked with Swift 6.2.4 in an isolated Docker
container: Codex/shared support passed Swift 6 type-checking, and OpenCode/tests
passed syntax parsing. Running the adapter XCTest suite was blocked before
adapter compilation by missing `sqlite3.h` in that image. Full test execution
remains delegated to the main agent's SQLite-equipped Docker environment; there
is no native Swift toolchain in this editing environment.
