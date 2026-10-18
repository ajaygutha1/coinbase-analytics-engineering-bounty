# ADR 0007 — Metric definitions live in YAML once; contested metrics change via model versions

**Status:** accepted · **Date:** 2026-09-29

## Context
A dashboard has reported "41% of weekly active users made a trade" for two years. A rebuilt model
says 34%. The gap is a user × device fan-out in the legacy query, and leadership has made decisions
on the old number. The PM asks for the new table to match the dashboard.

## Decision
Metrics are defined once, on the mart, in the dbt semantic layer (`daily_signups`,
`signup_to_trade_conversion_*`), so a dashboard reads a definition rather than owning one. A
contested metric is changed by **versioning the model**: `fct_weekly_active_traders` v1 reproduces
the legacy definition with a `deprecation_date`; v2 is the person-grain definition and
`latest_version`. `rpt_weekly_active_traders_bridge` decomposes the gap per country so the change
is one slide, and a test pins the bridge closing. The new table is never edited to match the old
number.

## Alternatives rejected
- **Change history in place.** One clean definition immediately, but a surprise in the deck and a
  broken trend line.
- **Leave the legacy metric.** Preserves continuity and the defect.
- **Make the new table match.** Encodes the fan-out into the new source of truth; the same seven
  points are rediscovered later with less goodwill.

## Consequences
Dual-run for two review cycles, restate history under v2 so the trend is continuous, name an owner,
retire v1 on the date in the YAML. dbt warns anyone still pinned to v1.
