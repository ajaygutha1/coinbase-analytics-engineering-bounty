#!/usr/bin/env python3
"""Generate the Exercise 3 / 4 fixture: 100 weekly active users, the trades and devices behind
the inherited weekly_active_traders.sql, and a country history table.

Column names mirror the challenge snippet exactly (users.country, trades.status,
trades.created_at, devices.is_active) so the legacy query can be run verbatim.

Planted facts (all deterministic):
  * 100 weekly active users across US / GB / DE / BR                -> the 41% / 34% denominator
  * 35 users with a completed trade (status 1 or 3) in the week
  * 34 of them own >= 1 active device; U035 owns only an inactive one -> dropped by the INNER JOIN (F4)
  * 7 traders own a second active device                              -> 41 user x device pairs (F1)
  * 2 failed trades (status 2) for otherwise non-trading users          -> must not count (F3)
  * one extra trade for U001 at 2024-01-08 03:00 UTC = Jan 7 19:00 PT   -> inside the PT week, outside
                                                                          the legacy UTC-string window (F2)
  * U001 and U058 moved country after the week                          -> users.country is today's country (F5)

Run: python scripts/ex3_make_fixtures.py   (rewrites seeds/ex3_*.csv)
"""
from __future__ import annotations

import csv
from pathlib import Path

SEEDS = Path(__file__).resolve().parents[1] / "seeds"


def country_for(i: int) -> str:
    if i <= 55:
        return "US"
    if i <= 75:
        return "GB"
    if i <= 90:
        return "DE"
    return "BR"


def write(name: str, header: list[str], rows: list[list]) -> None:
    with (SEEDS / name).open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)


def main() -> None:
    users, trades, devices, history = [], [], [], []
    trader_ids = [i for i in range(1, 101) if i % 3 == 1]          # 34 users
    multi_device = {1, 4, 7, 58, 61, 76, 91}                          # +7 pairs
    assert len(trader_ids) == 34 and multi_device <= set(trader_ids)

    for i in range(1, 101):
        uid = f"U{i:03d}"
        # Every user was active during the week (this table IS the weekly-active-user population).
        users.append([uid, country_for(i), f"2024-01-0{1 + (i % 7)} {10 + (i % 8):02d}:00:00"])

        if i == 35:
            # Completed trade but only an inactive device: dropped by the inner join in both versions.
            devices.append([f"D{i:03d}-1", uid, 0])
        else:
            devices.append([f"D{i:03d}-1", uid, 1])
        if i in multi_device:
            devices.append([f"D{i:03d}-2", uid, 1])
        if i in (12, 48):
            # Inactive spare devices must not create pairs.
            devices.append([f"D{i:03d}-9", uid, 0])

    tid = 0
    for i in trader_ids + [35]:
        tid += 1
        status = 1 if i == 4 else 3                                    # both codes mean completed
        trades.append([f"T{tid:03d}", f"U{i:03d}", status, f"2024-01-0{1 + (i % 7)} {12 + (i % 6):02d}:30:00"])
    for i in (2, 50):                                                   # failed trades
        tid += 1
        trades.append([f"T{tid:03d}", f"U{i:03d}", 2, "2024-01-03 14:00:00"])
    tid += 1                                                            # PT-week boundary trade
    trades.append([f"T{tid:03d}", "U001", 3, "2024-01-08 03:00:00"])

    # Country history: as-of the week, U001 was in GB and U058 was in US.
    for i in range(1, 101):
        uid = f"U{i:03d}"
        if i == 1:
            history.append([uid, "GB", "2023-01-01", "2024-03-01"])
            history.append([uid, "US", "2024-03-01", ""])
        elif i == 58:
            history.append([uid, "US", "2023-01-01", "2024-02-15"])
            history.append([uid, "GB", "2024-02-15", ""])
        else:
            history.append([uid, country_for(i), "2023-01-01", ""])

    write("ex3_users.csv", ["user_id", "country", "last_active_at"], users)
    write("ex3_trades.csv", ["trade_id", "user_id", "status", "created_at"], trades)
    write("ex3_devices.csv", ["device_id", "user_id", "is_active"], devices)
    write("ex3_user_country_history.csv", ["user_id", "country", "valid_from", "valid_to"], history)

    active_pairs = sum(1 for d in devices if d[2] == 1 and int(d[1][1:]) in trader_ids)
    print(f"users={len(users)} trades={len(trades)} devices={len(devices)} history={len(history)}")
    print(f"distinct traders with an active device={len(trader_ids)} user x device pairs={active_pairs}")
    assert active_pairs == 41


if __name__ == "__main__":
    main()
