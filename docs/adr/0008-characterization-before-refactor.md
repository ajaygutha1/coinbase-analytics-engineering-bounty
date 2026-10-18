# ADR 0008 — Characterize before refactoring; verify AI output by parity, never by its claim

**Status:** accepted · **Date:** 2026-09-29

## Context
A 400-line `weekly_active_traders.sql` with no tests, no documentation and no remaining author
powers a metric the business relies on, and the PM needs a new country cut of it before Friday.

## Decision
1. **Freeze the baseline.** The inherited core logic is kept verbatim in
   `analyses/ex3_legacy_weekly_active_traders.sql` and as `fct_weekly_active_traders` v1. It is the
   characterization snapshot, not something to fix.
2. **Refactor into named CTEs**, one per flag: typed window, decoded status, status in the `WHERE`,
   collapse to one row per person before joining, visible device rule, country as-of-week.
3. **Prove parity per country** with `analyses/ex3_parity_query.sql` and the
   `assert_ex3_refactor_parity_by_country` test. The refactor may differ from the legacy output
   only by the two named legacy defects (failed-only users in its `COUNT(DISTINCT)`, the device
   multiplier in `completed_trades`). Any other difference blocks the country cut.
4. **Ship the country cut from the refactor** and keep the legacy total on the slide until the
   definition conversation (ADR 0007) has happened.

AI tools are used to explain the original, propose the decomposition and enumerate test cases.
Their statement that two queries are equivalent is treated as a hypothesis; the parity query is
the evidence.

## Consequences
Delivering the new request does not quietly change a number people already rely on. The parity
query becomes a permanent model (`rpt_weekly_active_traders_bridge`), so the next refactor starts
with a test instead of an archaeology project.
