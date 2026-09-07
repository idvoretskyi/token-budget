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

Pricing should use the applicable profile effective at the event timestamp, not
apply today's rate blindly to historical usage. Keep distinct effective dates
when rates change. Missing applicable profiles, conflicting entries, and currency
mismatches require explicit handling; a missing price is not a zero price. The
model has no exchange-rate feed, account discount, or subscription entitlement.

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
Reset calculations must be calendar-aware, including daylight-saving transitions;
the exact boundary behavior needs tests rather than fixed-duration assumptions.

Changing a budget, scope, time zone, or profile changes the interpretation of the
estimate. It does not change the provider's billing period or past invoices.

## Incomplete Estimates

Missing history, source format changes, cumulative-counter ambiguity, dropped
records, unpriced models, and usage outside selected local sources can all affect
results. A user-entered coverage start is not proof of complete records. A partial
priced subtotal must not be presented as a guaranteed remaining allowance.

Taxes, negotiated rates, credits, free tiers, batch pricing, context-length tiers,
cache duration, tool fees, and subscription rules may not be represented by the
simple profile. Confirm actual charges with the provider independently. No billing
accuracy guarantee is offered.
