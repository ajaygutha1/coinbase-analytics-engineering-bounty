# Convenience targets. Everything CI runs is reachable from here.
export DBT_PROFILES_DIR := .
PY  ?= .venv/bin/python
DBT ?= .venv/bin/dbt

.PHONY: setup lint test build incremental prod-compile scripts docs all clean

setup:            ## create the venv and install pinned dependencies
	python3 -m venv .venv && $(PY) -m pip install -r requirements.txt -r requirements-dev.txt

lint:             ## ruff (Python) + sqlfluff (SQL) + static project checks
	.venv/bin/ruff check scripts tests_py
	.venv/bin/sqlfluff lint models tests analyses macros
	$(PY) scripts/static_validate.py

test:             ## Python unit tests for the Exercise 2 diagnostic
	$(PY) -m pytest

build:            ## seed + full-refresh build (models, contract, unit tests, data tests)
	$(DBT) seed --full-refresh
	$(DBT) build --full-refresh --exclude resource_type:seed

incremental:      ## second build: exercises the merge / delete+insert / watermark paths
	$(DBT) build --exclude resource_type:seed

replay:           ## inject a late-arriving event and prove the incremental path recomputes only that person
	DBT_BIN=$(DBT) $(PY) scripts/incremental_replay.py

prod-compile:     ## prove staging compiles against the production source() declarations
	$(DBT) compile --vars '{use_seed_sources: false}' --select resource_type:model

scripts:          ## Exercise 2 fixtures + blind diagnostic, Exercise 4 bridge, fixture oracle
	$(PY) scripts/ex2_make_fixtures.py
	$(PY) scripts/ex2_reconcile_signups.py
	$(DBT) compile --select ex2_reconciliation_in_sql && $(PY) scripts/ex2_sql_crosscheck.py
	$(PY) scripts/ex4_fanout_bridge.py
	$(PY) scripts/validate_funnel_fixture.py

docs:             ## dbt docs + Mermaid lineage in docs/LINEAGE.md
	$(DBT) docs generate
	$(PY) scripts/render_lineage.py

all: lint test build incremental replay prod-compile scripts docs

clean:
	rm -rf target logs coinbase_bounty.duckdb data/ex2/*.csv data/ex2/*.json
