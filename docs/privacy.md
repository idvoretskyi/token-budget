# Privacy

## Local Runtime

Token Budget's runtime boundary is local-only: no network calls, telemetry,
analytics, backend, automatic price downloads, or provider credentials. It does
not need an API key, account login, or billing portal access to estimate observed
usage. Development tools and GitHub CI do access the network to obtain toolchains,
dependencies, source code, and build artifacts; that is separate from app runtime.

## Data Handling

Enable only the sources you intend to inspect. The settings model defaults to no
enabled sources, no selected provider/model combinations, and notifications off.
Source files and databases are inputs, not data the app should modify.

The normalized model retains event identity, source, timestamp, provider, model,
and token counts. Settings contain selected local paths, budget configuration,
manual prices, and an optional coverage assertion. These are potentially sensitive
metadata even without prompts. Importing a file may require parsing records that
also contain private text; local processing is not the same as never reading
sensitive bytes. Raw prompt content must not be persisted as usage events or
included in diagnostic output.

The current app stores settings, scan status, and a SQLite usage ledger in its
`TokenBudget` Application Support directory. It requests owner-only directory
permissions and limits settings and scan-status file permissions. These code
paths have not been validated on a real Mac.

Local-only is not a claim of application-level encryption, secure erasure,
sandboxing, or a completed security audit. OS permissions, backups, and other local
processes can affect confidentiality. Notifications are not implemented and no
notification permission is requested. Any future notification visibility needs
separate privacy review.

Disabling a source excludes it from estimates but retains ledger history; a failed
scan also retains previously recorded usage. Neither operation erases backups.
Data-removal behavior and storage lifecycle need implementation-specific
verification before being advertised as a privacy guarantee.

## Safe Diagnostics

Import warnings are required to be static and public-safe. Never publish raw
logs, source databases, session files, authentication files, environment dumps,
personal paths, or real screenshots containing identifying data. Reproduce bugs
with invented input and report tool versions, a high-level description, and static
warning text only. Inspect any output before sharing; diagnostics are not a
substitute for review.

Use [private vulnerability reporting](../SECURITY.md) for security issues. Public
issues and CI artifacts are not private storage.
