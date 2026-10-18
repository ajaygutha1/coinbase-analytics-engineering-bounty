#!/usr/bin/env python3
"""Exercise 4 in twenty lines of Python, independent of dbt: show how "41% of weekly active users
made a trade" becomes 34% once a person counts once, and that the gap is entirely device fan-out.

Reads the same seeds the dbt models use, applies the legacy logic literally (comma join to
devices, status 1 or 3 inside the SUM), then the person-grain logic, and prints the bridge.
"""
from __future__ import annotations

import csv
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEEDS = ROOT / "seeds"
WEEK_START, WEEK_END = "2024-01-01", "2024-01-08"


def read(name: str) -> list[dict[str, str]]:
    with (SEEDS / name).open(newline="") as f:
        return list(csv.DictReader(f))


def main() -> None:
    users = read("ex3_users.csv")
    trades = [t for t in read("ex3_trades.csv") if WEEK_START <= t["created_at"] < WEEK_END]
    active_devices = defaultdict(int)
    for d in read("ex3_devices.csv"):
        if d["is_active"] == "1":
            active_devices[d["user_id"]] += 1

    # Legacy: FROM users, trades, devices WHERE ... AND d.is_active = 1  -> one row per trade x device
    legacy_rows = sum(active_devices[t["user_id"]] for t in trades if t["status"] in ("1", "3"))
    legacy_distinct_any_status = len({t["user_id"] for t in trades if active_devices[t["user_id"]] > 0})

    # Person grain: distinct users with a completed trade AND >= 1 active device
    completed_users = {t["user_id"] for t in trades if t["status"] in ("1", "3")}
    people = {u for u in completed_users if active_devices[u] > 0}
    dropped_no_device = completed_users - people
    failed_only = {t["user_id"] for t in trades if active_devices[t["user_id"]] > 0} - completed_users

    denominator = len(users)
    legacy_pct, people_pct = legacy_rows / denominator, len(people) / denominator
    print(f"weekly active users (denominator):           {denominator}")
    print(f"legacy numerator (completed trades x devices): {legacy_rows}  -> {legacy_pct:.0%}")
    print(f"person-grain numerator (distinct people):      {len(people)}  -> {people_pct:.0%}")
    gap = legacy_rows - len(people)
    print(f"gap explained by multi-device fan-out:         {gap} rows -> {legacy_pct - people_pct:.0%}")
    print(f"legacy COUNT(DISTINCT) any status:             {legacy_distinct_any_status} "
          f"(includes {len(failed_only)} failed-only users)")
    print(f"traders dropped by active-device rule:         {len(dropped_no_device)} ({sorted(dropped_no_device)})")

    assert denominator == 100 and legacy_rows == 41 and len(people) == 34
    assert legacy_distinct_any_status == 36 and len(failed_only) == 2 and len(dropped_no_device) == 1


if __name__ == "__main__":
    main()
