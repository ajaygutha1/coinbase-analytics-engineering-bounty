#!/usr/bin/env python3
"""Fast checks that do not require dbt/DuckDB. CI runs this in addition to dbt build."""
from __future__ import annotations

import csv
import re
from pathlib import Path

import yaml
from jinja2 import Environment

ROOT = Path(__file__).resolve().parents[1]
SKIP_DIRS = {".venv", "target", "dbt_packages", "logs", ".git", "__pycache__", "data"}


def project_files(pattern: str) -> list[Path]:
    """rglob that ignores build output and virtualenvs."""
    return [p for p in ROOT.rglob(pattern) if not (set(p.relative_to(ROOT).parts[:-1]) & SKIP_DIRS)]

REQUIRED = [
    "dbt_project.yml", "profiles.yml",
    "models/intermediate/int_funnel__events.sql",
    "models/intermediate/int_funnel__user_steps.sql",
    "models/marts/fct_onboarding_funnel.sql",
    "models/marts/fct_onboarding_funnel_daily.sql",
    "models/marts/rpt_signup_definition_bridge.sql",
    "models/weekly/fct_weekly_active_traders_v1.sql",
    "models/weekly/fct_weekly_active_traders_v2.sql",
    "models/utilities/metricflow_time_spine.sql",
    "analyses/ex3_legacy_weekly_active_traders.sql",
    "analyses/ex3_refactored_weekly_active_traders.sql",
    "analyses/ex3_parity_query.sql",
    "scripts/ex2_make_fixtures.py", "scripts/ex2_reconcile_signups.py", "scripts/ex2_diagnose.py",
    "scripts/ex3_make_fixtures.py", "models/weekly/rpt_weekly_active_traders_bridge.sql",
    "scripts/incremental_replay.py", "models/weekly/rpt_ex3_legacy_characterization.sql",
    "seeds/ex3_legacy_expected.csv",
    "scripts/ex4_fanout_bridge.py", "scripts/validate_funnel_fixture.py",
]


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    raise SystemExit(1)


def check_required() -> None:
    missing = [p for p in REQUIRED if not (ROOT / p).exists()]
    if missing:
        fail(f"missing required files: {missing}")


def check_yaml() -> None:
    for path in project_files("*.yml"):
        try:
            yaml.safe_load(path.read_text())
        except Exception as exc:
            fail(f"invalid YAML {path.relative_to(ROOT)}: {exc}")


def check_jinja() -> None:
    env = Environment()
    for path in project_files("*.sql"):
        try:
            env.parse(path.read_text())
        except Exception as exc:
            fail(f"invalid Jinja syntax {path.relative_to(ROOT)}: {exc}")


def check_csv_widths() -> None:
    for path in ROOT.joinpath("seeds").glob("*.csv"):
        with path.open(newline="") as f:
            rows = list(csv.reader(f))
        if not rows:
            fail(f"empty seed: {path.name}")
        width = len(rows[0])
        bad = [i + 2 for i, row in enumerate(rows[1:]) if len(row) != width]
        if bad:
            fail(f"ragged CSV {path.name} at lines {bad[:10]}")


def check_guardrails() -> None:
    events = (ROOT / "models/intermediate/int_funnel__events.sql").read_text()
    ledger = (ROOT / "models/staging/stg_ledger__transactions.sql").read_text()
    v2 = (ROOT / "models/weekly/fct_weekly_active_traders_v2.sql").read_text()
    required_fragments = {
        "stable on-chain semantic key": "'ledger|' || l.ledger_business_key",
        "ingestion watermark": "ingested_at_utc >= watermark.processed_wm",
        "LEFT JOIN identity retention": "left join identity",
        "USD precision safe cast": "safe_usd_amount",
        "raw amount preservation": "amount_raw",
        "fan-out-safe semi join": "where exists",
        "decoded status": "ledger_status_codes",
        "legacy query kept verbatim": "FROM {{ ref('ex3_users') }} u, {{ ref('ex3_trades') }} t, "
                                      "{{ ref('ex3_devices') }} d",
        "null-safe zero-address flag": "coalesce(lower(nullif(trim(cast(t.from_address as varchar)), '')) =",
        "UTC-safe load timestamp": "utc_now()",
    }
    bodies = {"stable on-chain semantic key": events, "ingestion watermark": events,
              "LEFT JOIN identity retention": events, "USD precision safe cast": ledger,
              "raw amount preservation": ledger, "fan-out-safe semi join": v2,
              "decoded status": v2,
              "legacy query kept verbatim": (ROOT / "analyses/ex3_legacy_weekly_active_traders.sql").read_text(),
              "null-safe zero-address flag": ledger,
              "UTC-safe load timestamp": (ROOT / "models/marts/fct_onboarding_funnel.sql").read_text()}
    for label, fragment in required_fragments.items():
        if fragment not in bodies[label]:
            fail(f"guardrail missing: {label}")



def check_refs() -> None:
    ref_re = re.compile(r"ref\(\s*[\'\"]([^\'\"]+)[\'\"]")
    available: set[str] = set()
    for path in list(ROOT.joinpath("models").rglob("*.sql")) + list(ROOT.joinpath("seeds").glob("*.csv")):
        available.add(path.stem)
        m = re.match(r"(.+)_v\d+$", path.stem)
        if m:
            available.add(m.group(1))
    missing: list[tuple[str, str]] = []
    for path in project_files("*.sql"):
        for ref_name in ref_re.findall(path.read_text()):
            if ref_name not in available:
                missing.append((str(path.relative_to(ROOT)), ref_name))
    if missing:
        fail(f"refs to missing models/seeds: {missing}")

def prose_word_count(markdown: str) -> int:
    # Challenge excludes code blocks. Remove fenced code and top note before counting.
    text = re.sub(r"```.*?```", " ", markdown, flags=re.S)
    text = re.sub(r"<!--.*?-->", " ", text, flags=re.S)
    return len(re.findall(r"\b[\w’'-]+\b", text))


def check_submission_word_count() -> None:
    path = ROOT / "submission" / "SUBMISSION_DRAFT.md"
    if not path.exists():
        return
    words = prose_word_count(path.read_text())
    if words > 1450:
        fail(f"submission prose is {words} words; target <=1450")
    print(f"submission prose word count (code excluded): {words}")


def main() -> None:
    check_required()
    check_yaml()
    check_jinja()
    check_csv_widths()
    check_guardrails()
    check_refs()
    check_submission_word_count()
    n_sql_tests = len(list(ROOT.joinpath("tests").glob("*.sql")))
    n_unit = (ROOT / "models/staging/_unit_tests.yml").read_text().count("  - name:")
    print(f"PASS: static checks; {n_sql_tests} singular SQL tests; {n_unit} unit-test definitions")


if __name__ == "__main__":
    main()
