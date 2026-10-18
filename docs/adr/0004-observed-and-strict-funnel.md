# ADR 0004 — Ship two funnel readings and name every disagreement

**Status:** accepted · **Date:** 2026-09-29

## Context
Events arrive out of order (a trade settles before the deposit feed catches up), late (a KYC
webhook retries for two days), or never (an ingestion gap). A funnel table has to decide what to
do with a person whose step 5 exists but whose step 4 does not, or is later.

## Decision
`fct_onboarding_funnel` carries both `furthest_step_observed` (highest terminal success ever seen,
any order; the reporting default) and `furthest_step_strict` (walk the steps in order and stop at
the first missing or out-of-order step). `has_sequence_anomaly = observed <> strict`, and
`data_quality_flags` names the reason (`trade_before_deposit`, `kyc_revoked_after_approval`,
`late_arriving_event`, …). A step advances only on its first **terminal success**; attempts,
pending states and rejections are counted but never advance it. Nothing is imputed and nobody is
dropped for being out of order.

## Alternatives rejected
- **Strict only.** Easy to reason about, brittle to any ingestion gap; a late webhook makes a
  converted user look stalled.
- **Observed only.** Robust, but can overstate a clean sequence and hides data-quality drift.
- **Impute missing steps** (e.g. "a trade implies a deposit"). Manufactures timestamps that do not
  exist; the next analyst cannot tell real from inferred.

## Consequences
The PM can choose per question, and "how many people have anomalies and why" is one `GROUP BY`
on the flags column (`rpt_funnel_data_quality`). The strict counts are tested to be monotonic and
never above observed.
