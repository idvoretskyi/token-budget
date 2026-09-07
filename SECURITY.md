# Security Policy

## Support Status

Token Budget is experimental, with no stable release support window or completed
security audit. Security fixes target the current default branch. Do not rely on
the app to enforce spending limits or establish billing correctness.

## Private Reporting

Use this repository's [private vulnerability reporting form](https://github.com/idvoretskyi/token-budget/security/advisories/new).
Private vulnerability reporting was confirmed enabled on 2026-09-07. Do not file
exploit details, private data, or vulnerabilities in public issues.

Include the affected revision, impact, and a minimal synthetic reproduction.
Do not send credentials, real session files, source databases, raw logs, or
personal paths, even in a private report. If you discover exposed credentials,
revoke them through their issuer rather than sending them to maintainers.

If the private form is unavailable, open a public issue asking only for private
reporting to be restored, without sensitive details. There is no guaranteed
response time or paid incident-response service.

## Security Boundaries

- Runtime operation is local-only: no telemetry, network price feed, login, or
  provider credentials.
- Treat usage files and databases as untrusted input, opened read-only. Malformed
  input must not cause raw data to appear in warnings or reports.
- Local usage metadata, settings, and selected paths can still be sensitive.
  Local-only does not imply encryption, secure deletion, or protection against
  another process running as the same user.
- CI processes source code and synthetic test data. It must not ingest real usage
  history or require signing secrets. Development artifacts are not notarized
  releases; signature verification alone does not establish trust in a publisher.

See [privacy](docs/privacy.md) for data handling and reporting guidance.
