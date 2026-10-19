# Changelog

All notable changes to this project. Dates are 2026.

## 10-18 — architecture diagrams and production mapping
- `docs/ARCHITECTURE.md`: eight Mermaid diagrams (system overview, quality gates by layer, life of an event, identity resolution, incremental and late arrivals, exercise map with the fan-out thread, CI pipeline, production mapping).
- README: system-overview diagram replaces the ASCII DAG; new Production mapping section with a component table and a construct-by-construct dialect table.
- README test counts corrected to the build output (PASS=238 WARN=2).
- Submission notes removed from the repository; `static_validate.py` no longer reads them.

## 09-30 — proofs instead of prose
- `scripts/incremental_replay.py`: injects a late-arriving KYC approval, runs the incremental path, asserts only the touched person was recomputed and the cohort moved by one. Runs in CI.
- Exercise 3 characterization test: `rpt_ex3_legacy_characterization` (verbatim legacy, per country) vs `seeds/ex3_legacy_expected.csv`; bridge decomposition tested to add back up to it.
- Unit test for identity failure paths: multi-hop and dangling merges are flagged, survivor test flag inherited.
- PR template with metric-impact and parity checklist; `make replay`.

## 09-30 — communication artifacts and cross-checks
- `docs/EXERCISE2_PM_MEMO.md`: the message to the PM before Friday (one number, definition, exact vs estimate, asks).
- `docs/EXERCISE4_TALK_TRACK.md`: what to say in the hallway, the one slide, what not to say.
- `analyses/ex2_reconciliation_in_sql.sql` + `scripts/ex2_sql_crosscheck.py`: the Exercise 2 bridge in SQL over the raw CSVs; CI asserts it matches the Python diagnostic line for line.
- `is_cohort_mature_7d` now uses the reporting zone's date, not the session's.
- README: "Review this repo in 10 minutes" and "Questions a reviewer might ask".

## 09-30 — fidelity pass against the challenge text
- Exercise 2: `scripts/ex2_diagnose.py`, a blind diagnostic over any three extracts; pytest coverage.
- Exercise 3: challenge SQL kept verbatim; fixture mirrors its columns; flag F6 (status filter inside the SUM) surfaced; per-country parity test; `country_as_of_week` from a history table.
- Exercise 4: denominator is weekly active users; `rpt_weekly_active_traders_bridge` per country.
- dbt groups + access, contracts on every mart, `rpt_funnel_data_quality`, eight ADRs, generated Mermaid lineage, ruff/sqlfluff/pytest lint job, Makefile, pre-commit, MIT licence, Pages workflow.

## 09-30 — build verification
- First real `dbt build` of the packaged project. Fixed: missing time spine (parse error); NULL zero-address flag that silently dropped every fiat deposit; local wall-clock in `_utc` columns; unread `vars.yml`; tautological test; silent DST spring-forward shift.
- Column-level schema docs and tests for every model; README; CI.

## 09-29 — design and first implementation
- Architecture brief, synthetic fixtures with planted traps, staging → identity → events → person × step → mart, semantic metrics, versioned weekly-active-traders, Exercise 2/4 scripts.
