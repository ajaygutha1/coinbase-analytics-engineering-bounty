# ADR 0001 — One row per person, keyed by a surrogate of the canonical account

**Status:** accepted · **Date:** 2026-09-29

## Context
The onboarding funnel is asked about in people: "how many users reached KYC". The three source
feeds each use a different identifier (UUID `account_id` in auth, numeric legacy id in KYC and the
ledger), people re-register and get merged by support, and internal QA accounts fire real events.

## Decision
`fct_onboarding_funnel` has exactly one row per `user_sk`, where `user_sk = md5(canonical_account_id)`
and the canonical account is the survivor after following the crosswalk's merge pointer. The
person keeps the **older** signup timestamp. `account_id` and `legacy_user_id` survive only as
debugging attributes. Identity resolution happens in one model, `int_identity__resolved`, which is
tested to be unique on both `account_id` and `legacy_user_id` so no downstream join can fan out.

## Alternatives rejected
- **`account_id` as the key.** Double-counts anyone who abandoned a signup and started again.
- **`email_hash` as the key.** People change emails; two people can share a hash (flagged, not keyed).
- **One row per event.** Correct as an audit trail (that is `int_funnel__events`) but forces every
  consumer to re-derive dedupe, retries and merges, which is how the Exercise 2–4 problems arise.

## Consequences
A merge re-keys a person's history, so the incremental models must re-process affected ids
(ADR 0005) and delete the orphaned key. Multi-hop merges and merges to a missing account are
flagged and fail the build rather than being resolved by guesswork.
