# ADR 0005 — Incremental models watermark on ingestion time with a lookback

**Status:** accepted · **Date:** 2026-09-29

## Context
The event feeds are large and append-mostly; the person table is small. Rebuilding everything on
every run is wasteful, but the usual shortcut, "process events with `event_time > last run`", loses
any event that happened on Monday and arrived on Thursday.

## Decision
`int_funnel__events` is an incremental `merge` on `event_key` whose watermark is
`max(ingested_at_utc)` from the existing table minus `incremental_lookback_days` (default 3).
Rows for any account or legacy id whose crosswalk entry changed inside the lookback are re-pulled
regardless of ingestion time, so a merge re-keys history. `int_funnel__user_steps` and
`fct_onboarding_funnel` recompute only people touched by those rows, and post-hooks delete keys
that no longer exist after a merge. The daily aggregate and the bridge are full-refresh because
they are cheap and a full rebuild guarantees restated cohorts are correct.

## Alternatives rejected
- **Watermark on event time.** Permanently skips late arrivals.
- **Watermark on the previous run's wall-clock time.** Mixes `timestamptz` with naive `timestamp`
  and drifts when a run is delayed; found and removed during build verification.
- **Full refresh everything.** Correct but scans all history per new event.

## Consequences
Runs must happen at least once per lookback window for the induction to hold, which is why the
lookback is a var. An upstream hard delete without a tombstone, or a backfill whose ingestion
timestamp is itself old, can evade an ingestion watermark; pair with CDC or periodic reconciliation.
The second `dbt build` in CI exercises this path on every push.
