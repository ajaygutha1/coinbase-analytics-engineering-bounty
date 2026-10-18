#!/usr/bin/env python3
"""Run the SQL version of the Exercise 2 reconciliation (analyses/ex2_reconciliation_in_sql.sql)
and assert it agrees with the Python diagnostic. Two independent implementations, one bridge.

Requires: python scripts/ex2_make_fixtures.py  and  dbt compile --select ex2_reconciliation_in_sql
"""
from __future__ import annotations

from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[1]
COMPILED = ROOT / "target" / "compiled" / "coinbase_bounty" / "analyses" / "ex2_reconciliation_in_sql.sql"

EXPECTED = {
    "system_c_raw_rows": 57_000,
    "exact_duplicate_rows": 4_000,
    "case_variant_ids": 1_000,
    "system_c_distinct_ids": 52_000,
    "system_a_distinct_ids": 52_000,
    "qa_accounts": 1_000,
    "previous_pt_day_accounts": 4_500,
    "verified_only_in_b": 3_156,
    "estimated_pacific_evening_signups": 3_507,
    "recommended_people_pt_day": 50_007,
    "system_b_distinct_ids": 45_003,
    "signed_up_not_verified": 5_004,
}


def main() -> None:
    if not COMPILED.exists():
        raise SystemExit(f"missing {COMPILED}; run: dbt compile --select ex2_reconciliation_in_sql")
    con = duckdb.connect()
    con.execute(f"set file_search_path = '{ROOT}'")
    rel = con.sql(COMPILED.read_text())
    row = dict(zip(rel.columns, rel.fetchone(), strict=True))
    width = max(len(k) for k in row)
    for key, value in row.items():
        print(f"{key:<{width}}  {int(value):>8,}")
    mismatches = {k: (int(row[k]), v) for k, v in EXPECTED.items() if int(row[k]) != v}
    assert not mismatches, f"SQL and Python disagree: {mismatches}"
    print("\nPASS: SQL reconciliation matches the Python diagnostic on every line")


if __name__ == "__main__":
    main()
