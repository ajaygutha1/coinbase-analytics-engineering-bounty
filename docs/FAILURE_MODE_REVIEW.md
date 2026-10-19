# Adversarial failure-mode review

Scope: every transformation in the synthetic dbt project, with special attention to high-precision crypto values, blockchain re-orgs/duplicates, incremental scan cost, fan-out, and LEFT JOIN behavior.

## Executive result

The review found and fixed several failure modes before packaging: ragged off-chain ledger fixture rows, non-deterministic first-success metadata on timestamp ties, hard-coded status values in the corrected Exercise 3 path, and insufficient preservation of raw high-precision values. The current design makes the metric’s grain explicit at each layer and treats data-quality uncertainty as a flag rather than silent row loss.

The repo still has **source-dependent limits** that no SQL can solve from the challenge text alone: a naive Pacific timestamp during the fall-back hour is ambiguous without an offset; a chain re-org cannot be inferred if the source never emits a reversal/canonicality update; and a source hard-delete cannot be detected by an append-only incremental feed without a tombstone or snapshot. Those are documented rather than guessed away.

## 1. High-precision crypto / overflow

**Failure mode:** casting a token amount directly to `BIGINT`, `DOUBLE`, or a too-small decimal can overflow or round. Ethereum-style base-unit integers can exceed 38 decimal digits, while common analytics warehouses cap fixed decimals around 38 digits.

**Implemented guardrail:** `stg_ledger__transactions` keeps `amount_raw` and `usd_notional_raw` as strings, then uses `try_cast` through `safe_crypto_amount()` / `safe_usd_amount()`. A failed parse becomes `has_*_precision_issue=true` rather than a build crash or a rounded value. The first-deposit threshold is evaluated on `DECIMAL(38,8)` USD notional and uses `coalesce(..., false)`, so an unparseable USD value cannot advance the funnel. Raw token-amount overflow is retained and flagged because the funnel only needs settled status + USD threshold.

**Test coverage:** unit fixture with an amount wider than `DECIMAL(38,18)`; singular test prevents a terminal deposit with an invalid USD notional.

**Production note:** if downstream analytics need exact uint256 arithmetic, keep base units as string/bytes and use a warehouse-specific 76–78 digit numeric/UDF. Do not convert to floating point.

## 2. Re-orgs, redelivery, and duplicate transaction entries

**Failure mode:** `tx_hash` is not a unique event key. One transaction can emit multiple logs, hashes can exist on multiple chains, and a re-org can restate an event. Deduping on `txn_id` alone also misses two ledger records that describe the same on-chain event.

**Implemented guardrail:** staging removes exact ledger re-deliveries by latest `txn_id`; the canonical event layer uses `chain_id + tx_hash + log_index` for on-chain semantics and `txn_id` for off-chain rails. Its incremental `unique_key` is the resulting stable `event_key`, so a later restatement such as `settled → reversed` updates the event instead of adding a second success. The seed contains an old settled deposit, a later reversal under the same natural key, and a replacement deposit.

**Test coverage:** natural event keys are unique; the reversed restatement wins; the replacement—not the orphaned event—becomes first deposit; a batched hash with two log indexes yields two deposits, while an exact redelivery does not create a third.

**Residual dependency:** this only works if upstream supplies a reversal/canonicality restatement. If it does not, the model cannot discover chain consensus from these columns alone; production should ingest a canonical block/log status or tombstone feed.

## 3. Incremental correctness and massive scans

**Failure mode:** filtering incrementals on event time permanently misses events that happened Monday but arrived Thursday. Recomputing all history for each new event is also unnecessarily expensive.

**Implemented guardrail:** `int_funnel__events` watermarks on ingestion time with a configurable three-day reprocessing window. If the identity crosswalk changes, historical source rows for only the affected account/legacy ids are pulled back through identity resolution. `int_funnel__user_steps` recomputes only touched people, and `fct_onboarding_funnel` merges only touched `user_sk` values. The daily aggregate is deliberately cheap enough to rebuild fully.

**Correctness detail:** cleanup post-hooks remove stale person keys after an account merge/rekey so a prior surrogate does not remain as a ghost row.

**Residual dependency:** a backfill whose *ingestion timestamp itself is old*, or an upstream hard delete without a tombstone, can evade an append-mostly watermark. In production, pair this with source snapshots/change-data-capture or periodic deep reconciliation.

## 4. LEFT JOIN mismatches and silent row loss

**Failure mode:** an inner join to identity or devices makes unmatched users disappear, which can look like a real conversion drop.

**Implemented guardrail:** source events LEFT JOIN the one-row-per-id identity model. Unresolved ids remain in `int_funnel__events` with `is_identity_unresolved=true`; a warn-level test surfaces their count. Trusted marts exclude them only at the point where person grain is required. Exercise 3’s active-device rule is an `EXISTS` semi-join, so device multiplicity cannot multiply traders.

**Test coverage:** account and legacy ids are unique in the crosswalk; mart signups reconcile to eligible signed-up people in the event layer; unresolved users remain upstream but cannot leak into the mart; person×step grain has a uniqueness invariant.

## 5. Fan-out and metric inflation

**Failure mode:** joining one trade row to N active devices produces N rows. A `COUNT(DISTINCT user_id)` may hide the problem for one metric while `COUNT(*)`, sums, or subsequent joins remain inflated.

**Implemented guardrail:** collapse/semijoin before aggregation. The Exercise 3/4 fixture contains 34 trading people and 41 active device rows among 100 signup users. v1 intentionally reproduces 41%; v2 counts 34% at person grain. The parity analysis reports the exact seven excess rows/device multiplier rather than merely saying the old query is “wrong.”

**Test coverage:** a singular test asserts `41 → 34` exactly on the planted fixture.

## 6. Time zones and DST

**Failure mode:** UTC-date grouping shifts late-evening Pacific signups into the next day. The ledger also supplies naive local timestamps, and 01:00–01:59 on the fall-back date occurs twice.

**Implemented guardrail:** every canonical event timestamp ends `_at_utc`; `signup_date_pt` is derived from the UTC instant through a named reporting-zone variable. Ledger-local timestamps go through one macro. Rows in the ambiguous fall-back hour receive `is_dst_ambiguous_local_time=true` rather than pretending the offset is known.

**Residual dependency:** a naive timestamp cannot tell which occurrence of the repeated hour it meant. The durable production fix is for the producer to send an offset-aware instant or a separate UTC timestamp.

## 7. Funnel semantics / double counting

**Failure mode:** counting attempts, pending states, or later retries as separate people inflates funnel stages. For KYC, `rejected → approved` is normal; `approved → revoked` should not erase the historical fact that approval occurred if the question is onboarding completion.

**Implemented guardrail:** first terminal success advances each step. Negative attempts and revocations are separate counters/flags. The user-step table has one row per `user_sk × funnel_step`, and first-success metadata is chosen deterministically by `(event_at_utc, event_key)`.

The mart ships two readings: `furthest_step_observed` (highest success ever seen) and `furthest_step_strict` (walk in sequence and stop at missing/out-of-order data). `has_sequence_anomaly` and named flags quantify the disagreement.

## 8. Metric contract and dashboard drift

**Failure mode:** the SQL is corrected but a dashboard keeps its own denominator, time zone, or legacy definition.

**Implemented guardrail:** the daily mart embeds dbt 1.12 semantic annotations. Weekly active traders is a versioned model: v1 is the legacy user×device definition with a deprecation date, v2 is the person-grain definition. This supports a controlled dual-run rather than silently rewriting history.

## 9. What to run before a release

```bash
export DBT_PROFILES_DIR=.
dbt seed
dbt build --exclude resource_type:seed
python scripts/ex2_make_fixtures.py
python scripts/ex2_reconcile_signups.py
python scripts/ex4_fanout_bridge.py
python scripts/static_validate.py
```

Acceptance criteria: dbt errors = 0; only the planted unresolved-identity test warns; Exercise 2 residual = 0; Exercise 4 prints 41% legacy and 34% person-grain; CI is green on the public repo.
