# ADR 0006 — Exclusions are flags upstream and filters only in marts

**Status:** accepted · **Date:** 2026-09-29

## Context
Some rows must not count: QA accounts, events whose id resolves to no person, deposits from the
zero address, dust below the threshold, unparseable amounts. The easy fix is a `WHERE` clause in
staging. The cost is that nobody can later ask "how many did we exclude, and why".

## Decision
Staging never filters rows. `int_funnel__events` keeps every event and attaches booleans
(`is_test_account`, `is_identity_unresolved`, `is_from_zero_address`, `has_usd_precision_issue`,
`is_late_arriving`, …). `is_terminal_success` is computed from those flags and is tested to be
two-valued, because a NULL in an `AND … NOT …` chain silently drops the row from every aggregate
(the fiat-deposit bug found in build verification). Person-grain marts exclude test accounts and
unresolved identities at the last possible point; a warn-level test counts the unresolved rows so
the pipeline keeps shipping while someone investigates.

## Alternatives rejected
- **Filter in staging.** Cheapest, but the exclusion is invisible and a reconciliation between raw
  and mart cannot be explained.
- **Inner-join to identity.** Turns an identity-team backlog into a fake conversion drop.

## Consequences
Every exclusion is one `GROUP BY` away, `assert_mart_signups_reconcile_to_events` can prove the mart
lost nothing it should have kept, and the unresolved row planted in the fixture is a warning, not
an error, by design.
