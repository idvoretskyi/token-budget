# Pricing and Budgets

Token Budget estimates the price of **observed local usage**, not the amount a
provider will charge. It cannot verify account-wide activity or subscription
allowances and does not stop requests when a budget is exceeded.

## Manual Dated Profiles

Initial pricing is manual. A `PriceProfile` identifies a source, provider, model,
currency, effective start date, provenance, and decimal rates per million tokens
for input, cache reads, cache writes, and output. Record where and when you checked
a rate. There is no automatic refresh or guarantee that a user-entered rate matches
current provider terms.

Pricing selects the latest profile effective at or before the event timestamp,
matching source, provider, model, and budget currency exactly. Today's rate is not
applied blindly to historical usage. Keep distinct effective dates when rates
change. Duplicate scope/currency/effective instants are rejected. Missing applicable
profiles, including currency mismatches, count as unpriced usage, not zero cost.
The model has no exchange-rate feed, account discount, or subscription entitlement.

For disjoint normalized token counts, the estimate is:

```text
cost = (input * inputRate
      + cacheRead * cacheReadRate
      + cacheWrite * cacheWriteRate
      + output * outputRate) / 1,000,000
```

Use decimal arithmetic for money; display rounding must not redefine underlying
cost. Adapters must normalize whether cached tokens are included in a source's
input total and whether counters describe one event or cumulative usage.

For a purely synthetic arithmetic example, 1,000 input tokens at 2 currency units
per million and 500 output tokens at 8 units per million produce 0.006 units.
These are invented numbers, not a provider price recommendation.

## Scope and Periods

A selection is an exact source/provider/model combination. A budget covers only
the selected combinations from enabled sources, not all models, all providers,
all devices, or an entire account. Review scope before interpreting a total.

Periods are weekly or monthly in the stored `timeZoneID`, independent of later
system time-zone changes. Weekly configuration includes weekday and reset time;
monthly periods use the first day of the month and configured reset time, not a
rolling 30-day window. The initial model defaults to UTC, Monday, and 00:00.
The engine uses the Gregorian calendar and resolves each reset's civil day
independently, with these explicit daylight-saving policies:

- A nonexistent reset time moves forward to the next valid wall-clock time
  (`.nextTime`). For example, a skipped 02:30 reset becomes 03:00, not 03:30.
- A repeated reset time uses its first occurrence (`.first`), with no second reset
  when the clock repeats that time.
- A midnight gap affects only the relevant reset day; it must not shift unrelated
  weekly or monthly boundaries.
- Windows include their start and exclude their end. At an exact reset instant,
  the new period begins. Future events are excluded from the current estimate.
- Durations follow calendar boundaries, not fixed seconds: a DST-transition week
  may have 167 or 169 hours, and calendar months vary in length.

Portable regression tests cover these policies, subsecond boundaries, leap years,
year rollover, and stored-zone reset times. They passed on Linux and macOS 26 in
the [recorded 78-test CI run](ci.md), but do not replace interactive validation.

Changing a budget, scope, time zone, or profile changes the interpretation of the
estimate. It does not change the provider's billing period or past invoices.

## Forecast Policy

The core can extrapolate `spent * periodDuration / elapsedDuration` only when the
user-confirmed coverage start is at or before the period start, at least 86,400
seconds (24 hours) have elapsed, and selected usage is fully priced with no actual
import problems or unknown warnings. It uses actual elapsed and period durations,
including DST, rather than a fixed-length week or month.

The current implementation shares `UsageCoverage.isInformationalWarning` with
alerts. Its exact allowlist permits the general local-coverage disclaimer,
OpenCode's canonical step-finish notice, and Codex's recorded-model-attribution
notice, including source-prefixed forms. These notices remain visible; they are
not evidence of a specific import gap and do not by themselves suppress a forecast.
The unconfirmed-history disclaimer is also informational, but does not bypass the
separate requirement for confirmed coverage starting at or before the window.

Malformed, missing, unsupported, deferred, or otherwise incomplete imports, unknown
warnings, and unpriced usage still suppress forecasts. User confirmation is an
assertion, not proof of complete billing history. This policy's regression tests
passed in the [verified 78-test CI run](ci.md); real installation behavior with
user data remains unvalidated.

## Optional Alerts

Notifications are off by default. Enabling them and applying settings requests
macOS alert/sound permission. `BudgetAlerts` watches eligible scan summaries for
new crossings of 80% and 100% of the configured budget, using observed priced spend,
not a forecast, bill, or remaining allowance.

The first eligible scan after startup, configuration/period changes, or a rejected
summary establishes a silent baseline. Already reached thresholds are consumed
without historical alerts. Missing prices, failed scans, unavailable estimates,
and non-allowlisted warnings suppress alerts and reset that baseline. Alerts and
forecasts share the informational-warning allowlist; unknown warnings fail closed.
Unlike forecasts, alerts do not require confirmed full-period history or 24 elapsed
hours because they describe observed threshold crossings, not extrapolated totals.

Threshold records are persisted in the local ledger for the budget, period,
enabled sources, selection fingerprint, and threshold. They are recorded before
delivery to prevent later floods. Denied permission, a crash, or delivery failure
can therefore lose an alert rather than retry it. Repeated scans and downward
corrections do not reissue consumed thresholds. Notifications are best-effort;
native permission and delivery behavior remain unvalidated.

## Incomplete Estimates

Missing history, source format changes, cumulative-counter ambiguity, dropped
records, unpriced models, and usage outside selected local sources can all affect
results. A user-entered coverage start is not proof of complete records. A partial
priced subtotal must not be presented as a guaranteed remaining allowance.

Taxes, negotiated rates, credits, free tiers, batch pricing, context-length tiers,
cache duration, tool fees, and subscription rules may not be represented by the
simple profile. Confirm actual charges with the provider independently. No billing
accuracy guarantee is offered.
