# ADR 0003 — Store UTC, report Pacific, flag DST edge cases instead of guessing

**Status:** accepted · **Date:** 2026-09-29

## Context
Three timestamp encodings arrive: ISO-8601 with `Z` (auth), epoch milliseconds that are sometimes
seconds (KYC), and naive Pacific wall-clock strings with no offset (ledger). The Growth review is
held in Pacific time, and 17:00–24:00 PT is the next UTC day, a band that holds a quarter of US
signups. A naive local timestamp is ambiguous for one hour each November and nonexistent for one
hour each March.

## Decision
Every timestamp column leaving staging is a naive `TIMESTAMP` holding the UTC instant and ends in
`_at_utc`; one macro per encoding does the conversion (`macros/timezones.sql`). Reporting dates end
in `_pt` and are derived from the UTC instant through the `reporting_timezone` var. The ledger's
zone is the `source_ledger_timezone` var, never a literal. Rows in the DST fall-back hour or the
spring-forward gap get `is_dst_ambiguous_local_time` / `is_dst_nonexistent_local_time` rather than a
silently chosen offset. Anything compared with "now" uses `utc_now()`, because comparing a naive
column with `current_timestamp` silently applies the session zone.

## Alternatives rejected
- **Store local time.** Unambiguous only if every consumer knows the zone; DST makes it wrong twice a year.
- **Report UTC days.** Puts late-evening Pacific signups on the wrong cohort day; this is the
  4,500-row line in the Exercise 2 bridge.

## Consequences
`signup_date_utc` and `signup_date_pt` are both kept so the boundary is auditable, and a test
asserts they never differ by more than one day. The durable fix for the ambiguous hour is an
offset-aware instant from the producer; until then the flag is the honest answer.
