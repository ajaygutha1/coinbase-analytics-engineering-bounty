#!/usr/bin/env python3
"""Create deterministic signup extracts whose reported counts are 52K / 45K / 57K."""
from __future__ import annotations

import csv
from datetime import UTC, datetime, timedelta
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / "data" / "ex2"
OUT.mkdir(parents=True, exist_ok=True)

BASE = datetime(2026, 9, 14, tzinfo=UTC)


def uid(i: int) -> str:
    return f"ACC-{i:05d}"


def write_csv(path: Path, fieldnames: list[str], rows: list[dict]) -> None:
    with path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(rows)


def main() -> None:
    a_rows: list[dict] = []

    # 1,000 QA/test accounts on the UTC day.
    for i in range(1, 1001):
        ts = BASE + timedelta(hours=12, seconds=i % 3600)
        a_rows.append({"account_id": uid(i), "created_at_utc": ts.isoformat(), "email": f"qa{i}@qa.coinbase.test"})

    # 4,500 production accounts between 00:00Z and 06:59Z: previous Pacific calendar day.
    for i in range(1001, 5501):
        seconds = (i - 1001) % (7 * 3600)
        ts = BASE + timedelta(seconds=seconds)
        a_rows.append({"account_id": uid(i), "created_at_utc": ts.isoformat(), "email": f"p{i}@example.com"})

    # 46,500 production accounts between 07:00Z and 23:59Z: same Pacific day.
    for i in range(5501, 52001):
        seconds = (i - 5501) % (17 * 3600)
        ts = BASE + timedelta(hours=7, seconds=seconds)
        a_rows.append({"account_id": uid(i), "created_at_utc": ts.isoformat(), "email": f"p{i}@example.com"})

    assert len(a_rows) == 52_000
    write_csv(OUT / "system_a.csv", ["account_id", "created_at_utc", "email"], a_rows)

    # System B defines signup as email-verified and uses the Pacific day.
    # Verified in-day from A: 41,847; verified late-evening PT from the next UTC date: 3,156.
    b_rows: list[dict] = []
    for row in a_rows[5500 : 5500 + 41_847]:
        b_rows.append({"user_id": row["account_id"], "verified_at_utc": row["created_at_utc"]})

    late_rows: list[dict] = []
    for j in range(1, 3508):
        i = 52000 + j
        # 00:00Z-06:59Z on Sep 15 is still Sep 14 PT.
        seconds = (j - 1) % (7 * 3600)
        ts = BASE + timedelta(days=1, seconds=seconds)
        late_rows.append({"account_id": uid(i), "created_at_utc": ts.isoformat(), "email": f"late{i}@example.com"})

    for row in late_rows[:3156]:
        b_rows.append({"user_id": row["account_id"], "verified_at_utc": row["created_at_utc"]})

    assert len(b_rows) == 45_003
    write_csv(OUT / "system_b.csv", ["user_id", "verified_at_utc"], b_rows)

    # System C is raw event rows: 52K originals + 4K exact re-deliveries + 1K case variants.
    c_rows = [dict(r) for r in a_rows]
    c_rows.extend(dict(r) for r in a_rows[:4000])
    for r in a_rows[4000:5000]:
        dup = dict(r)
        dup["account_id"] = dup["account_id"].lower()
        c_rows.append(dup)

    assert len(c_rows) == 57_000
    write_csv(OUT / "system_c.csv", ["account_id", "created_at_utc", "email"], c_rows)

    # Kept only for validating the planted truth; the reconciliation script does not require it.
    write_csv(OUT / "late_pt_truth.csv", ["account_id", "created_at_utc", "email"], late_rows)

    print("system_a rows: 52,000")
    print("system_b rows: 45,003")
    print("system_c rows: 57,000")


if __name__ == "__main__":
    main()
