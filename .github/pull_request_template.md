## What changes

<!-- One paragraph. Name the model(s) and the grain they claim. -->

## Metric impact

- [ ] No metric definition changes
- [ ] A metric definition changes → new model **version** added, old version given a `deprecation_date`, bridge model updated, ADR written or amended

## Checks

- [ ] `make lint test build incremental` is green locally
- [ ] New planted case in `seeds/` has a matching test (or unit test) and a row in the README table
- [ ] Any new column on a mart has a description, a `data_type` in the contract, and at least one test
- [ ] If an incremental model changed: `python scripts/incremental_replay.py` passes
- [ ] If Exercise 3 logic changed: `assert_ex3_legacy_characterization_frozen` still passes (the baseline did not move) and `assert_ex3_refactor_parity_by_country` still passes
- [ ] `docs/LINEAGE.md` regenerated if the DAG changed

## Who needs to know

<!-- Exposure owners affected (see models/marts/_exposures.yml), and the sentence you will send them. -->
