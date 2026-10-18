# Build verification review (2026-09-30)

Scope: the packaged project from the Phase 2/3 pass had never been executed against dbt or
DuckDB. This review ran it for real (dbt-core 1.12.5, dbt-duckdb 1.11.0, DuckDB 1.5.6), fixed
what broke, and re-checked every planted case against the design table. It complements
`FAILURE_MODE_REVIEW.md`, which is a desk review of failure modes.

## What was wrong, in order of severity

| # | Severity | Finding | Root cause | Fix | Regression guard |
|---|---|---|---|---|---|
| 1 | Build-breaking | `dbt parse` failed: the semantic layer requires a day-grain time spine and none existed. | `_marts.yml` declared metrics; the project never had a time spine model. | `models/utilities/metricflow_time_spine.sql` (DuckDB `generate_series`, no packages). | CI parses on every push. |
| 2 | Correctness (silent) | **No fiat deposit ever counted.** Six of eight people never reached step 4; Grace read 5/3 instead of the claimed 5/4. | `is_from_zero_address` was `lower(from_address) = '0x000…'`, which is NULL when `from_address` is NULL (fiat). `settled AND usd >= 1 AND NOT NULL` is NULL, so `is_terminal_success` was NULL and `min(...) filter (where ...)` skipped the row. | `coalesce(... = zero_address, false)` in staging. | `assert_settled_deposits_above_threshold_are_successes`, `assert_terminal_success_is_never_null`, `assert_fiat_and_onchain_rails_both_reach_first_deposit`, unit test with a null-address fiat row. |
| 3 | Correctness (mislabeled) | `_loaded_at_utc` / `_processed_at_utc` held local wall-clock time. | `cast(current_timestamp as timestamp)` strips the zone using the *session* zone. | `utc_now()` macro = `timezone('UTC', current_timestamp)`. | Static guardrail; `assert_no_future_events` now compares against `utc_now()`. |
| 4 | Correctness (latent) | `assert_no_future_events` compared a naive UTC column with `current_timestamp`. On a Pacific machine any event in the last 7 hours would be "in the future". | Same session-zone coercion. | Compare against `utc_now()`. | — |
| 5 | Configuration | `vars.yml` was never read. dbt only reads `vars:` from `dbt_project.yml` (or `--vars`). Every `var()` silently used its inline default. | Wrong file. | Vars moved into `dbt_project.yml`; `vars.yml` deleted. | Static check requires no `vars.yml`. |
| 6 | Incremental design | Ingestion watermark was `max(_processed_at_utc)` (a run time) compared to `ingested_at_utc` (a source time), mixing `timestamptz` and naive `timestamp`. | Type mix + wrong reference point. | Watermark is `max(ingested_at_utc)` from `{{ this }}`, as the design doc specifies. | Second `dbt build` in CI exercises the incremental path. |
| 7 | Test quality | `accepted_values` on `event_name` had `where: event_name in (...)`, making it a tautology. | Copy-paste. | Removed the `where`; severity `warn` so upstream noise surfaces without blocking. | — |
| 8 | DST | Spring-forward gap (02:xx on the March change date) was silently shifted +1h; the November heuristic was hard-coded to hour 1 / first Sunday. | Inline calendar arithmetic. | Zone-agnostic round-trip macros `is_dst_ambiguous_local` / `is_dst_nonexistent_local`; both flagged, neither guessed. | Unit test `ledger_dst_edge_cases_are_flagged_not_guessed`. |
| 9 | Fidelity | Weekly-active-trader v1/v2 hard-coded `date '2026-09-07'` and `100` signups and applied no week window. | Proof-of-concept shortcut. | Both versions derive the PT week from `ex3_week_start_pt`, filter trades to it, and count signups from `ex3_users`. Results unchanged (41 / 34 / 100). | `assert_legacy_fanout_gap_exact`. |
| 10 | Completeness | The signup-definition bridge lacked the UTC-day and verified-only definitions, i.e. the two that actually explain 52K vs 45K. | — | Added `distinct_accounts_utc_day` and `distinct_people_verified_pt`. | Column tests. |
| 11 | Hygiene | `pandas` pinned but unused; `dbt-core==1.12.0` pinned while 1.12.5 is current; `.user.yml` (dbt telemetry cookie) shipped in the zip; resume PDF and submission drafts sat at repo root. | — | Requirements pinned to the versions that ran; `.user.yml` ignored; personal/submission material moved to `submission/` with the PDF git-ignored. | — |

## What was checked and found correct

- On-chain natural key `chain_id:tx_hash:log_index`; Alice's re-org restatement wins and her replacement deposit is first; Carol's batched transaction yields two deposits and the exact re-delivery is dropped.
- Identity: one row per account and per legacy id; Judy's merge collapses to one person keyed to the surviving account with the older signup; the QA account is excluded; customer_ref 9999 is retained upstream and warns.
- KYC: Bob's rejected → approved converts with `kyc_negative_events = 1`; Heidi's revocation is a flag, not an erasure; Ivan stalls at 2/2.
- Pacific boundary: 06:58Z lands on the previous PT day; `signup_date_utc` and `signup_date_pt` never differ by more than one day.
- Precision: a 39-digit amount becomes a flag; an unparseable USD notional can never advance the deposit step.
- Exercise 2 and 4 scripts reproduce 57,000 → 52,000 → 50,007 → 45,003 (residual 0) and 41% vs 34%.

## Final state

`dbt build --full-refresh` and a following incremental `dbt build`: **0 errors, 2 intended warnings**
(both are customer_ref 9999). `dbt compile --vars '{use_seed_sources: false}'` succeeds, proving
the staging layer can be pointed at production `source()` declarations without SQL changes.

## Second pass (2026-09-30): fidelity to the challenge text

The live challenge page was re-read line by line and the repo was changed wherever it answered a
slightly different question than the one asked.

| Challenge says | Repo did | Repo now does |
|---|---|---|
| Ex 2: "Write a short Python script to programmatically identify where the systems diverge — starting with duplicate user IDs in System C." | Asserted planted causes it already knew. | `scripts/ex2_diagnose.py` is a blind diagnostic that works on any three extracts (column detection, three flavours of duplicate, set algebra, UTC hour histogram, QA patterns, definition signals, bridge + residual). `ex2_reconcile_signups.py` runs it on the generated fixtures and asserts it recovers every cause; `tests_py/` unit-tests each check. |
| Ex 3 snippet: `FROM users u, trades t, devices d … t.status = 1 OR t.status = 3 … t.created_at >= '2024-01-01' … d.is_active = 1` | Paraphrased with explicit joins, `status_code`, `completed_at_utc`, 2026 dates. | Legacy analysis and `fct_weekly_active_traders` v1 carry the snippet **verbatim**; the fixture uses the snippet's column names and the week of 2024-01-01. This surfaced a defect the paraphrase had hidden: the status filter is only inside the `SUM`, so `active_traders` also counts failed-only users (36 vs 34 on the fixture). |
| Ex 3: "how you'd get the country segment request done without breaking a metric" | Total-level parity only. | `analyses/ex3_parity_query.sql`, `rpt_weekly_active_traders_bridge` and `assert_ex3_refactor_parity_by_country` prove parity per country; the refactor also returns `country_as_of_week` from a history table (flag F5) next to the parity column. |
| Ex 3: "If you'd use AI tools … how you'd verify the output before trusting it" | Not addressed in the repo. | ADR 0008 and the refactor header state the protocol: AI explains and proposes, the parity query verifies; its claim of equivalence is a hypothesis. |
| Ex 4: "41% of weekly active **users** made a trade" | Denominator named `weekly_signups`. | Denominator is `weekly_active_users` from the population table; metric renamed `trader_share_of_active_users`. Same 41 / 34 / 100. |

Engineering polish added in the same pass: dbt groups with `protected` staging/intermediate and
`public` marts, enforced contracts on every mart (daily, bridge, weekly v1/v2, weekly bridge), an
observability mart (`rpt_funnel_data_quality`), eight ADRs, Mermaid lineage generated from the
manifest, ruff + sqlfluff + pytest in a separate CI lint job, a Makefile, pre-commit config, MIT
licence, and a manual GitHub Pages workflow for the dbt docs site.

Final state after the pass: `dbt build --full-refresh` **250 pass, 2 intended warnings, 0 errors**;
incremental build 214 pass; ruff and sqlfluff clean; 5 pytest tests pass; all proof scripts pass.
