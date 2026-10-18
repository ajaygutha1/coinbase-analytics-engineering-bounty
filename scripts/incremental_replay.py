#!/usr/bin/env python3
"""End-to-end proof that the incremental path handles a LATE-ARRIVING event correctly.

The claim in the design is: "a Monday KYC approval that arrives Thursday still updates Monday's
cohort, and only the touched person is recomputed." A second `dbt build` on unchanged data does
not prove that. This script does:

  1. Snapshot the person mart after a full-refresh build.
  2. Inject one late event straight into the seeded KYC table: Ivan (ACC-0007 / legacy 1007), whose
     case k7 was stuck in `pending`, gets an `approved` row whose event time is inside the fixture
     week but whose ingestion time is NOW.
  3. Run an ordinary incremental `dbt build` from the event layer down.
  4. Assert: Ivan is now identity-verified with the injected instant; his observed/strict step
     moved 2 -> 3; his row is the ONLY row whose `_loaded_at_utc` changed; the Sep-14 cohort's
     KYC count rose by exactly one; every other person's row is byte-identical.
  5. Restore the seed table and full-refresh so the repo is left as it was found.

Run after `dbt seed && dbt build --full-refresh`. Exit code is non-zero on any failed assertion.
"""
from __future__ import annotations

import os
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "coinbase_bounty.duckdb"
DBT = os.environ.get("DBT_BIN", "dbt")
IVAN_ACCOUNT = "ACC-0007"
IVAN_LEGACY = "1007"
INJECTED_EVENT_UTC = datetime(2026, 9, 14, 21, 30, tzinfo=UTC)          # inside the fixture week
INJECTED_ROW_ID = "k7-late-replay"


def dbt(*args: str) -> None:
    cmd = [DBT, *args]
    print("$", " ".join(cmd), flush=True)
    env = {**os.environ, "DBT_PROFILES_DIR": os.environ.get("DBT_PROFILES_DIR", ".")}
    subprocess.run(cmd, cwd=ROOT, env=env, check=True)


def mart_snapshot(con: duckdb.DuckDBPyConnection) -> dict[str, tuple]:
    rows = con.execute("select * from analytics.fct_onboarding_funnel order by user_sk").fetchall()
    cols = [d[0] for d in con.description]
    return {r[cols.index("user_sk")]: dict(zip(cols, r, strict=True)) for r in rows}


def daily_kyc(con: duckdb.DuckDBPyConnection) -> dict:
    return dict(con.execute(
        "select signup_date_pt, users_identity_verified_observed from analytics.fct_onboarding_funnel_daily"
    ).fetchall())


def main() -> int:
    con = duckdb.connect(str(DB))
    before = mart_snapshot(con)
    before_daily = daily_kyc(con)
    ivan_before = next(r for r in before.values() if r["account_id"] == IVAN_ACCOUNT)
    assert ivan_before["identity_verified_at_utc"] is None, "fixture drift: Ivan should start un-verified"
    assert ivan_before["furthest_step_observed"] == 2

    injected_ms = int(INJECTED_EVENT_UTC.timestamp() * 1000)
    ingested_now = datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    con.execute(
        "insert into analytics.raw_kyc_events "
        "(case_id, customer_ref, status, updated_at_ms, attempt_no, vendor, ingested_at) "
        "values (?, ?, ?, ?, ?, ?, ?)",
        ["k7", IVAN_LEGACY, "approved", injected_ms, 2, INJECTED_ROW_ID, ingested_now],
    )
    con.close()
    print(
        f"injected late KYC approval for {IVAN_ACCOUNT}: "
        f"event {INJECTED_EVENT_UTC:%Y-%m-%d %H:%M} UTC, ingested {ingested_now}"
    )

    try:
        dbt("build", "--select", "int_funnel__events+", "--exclude", "resource_type:seed")

        con = duckdb.connect(str(DB), read_only=True)
        after = mart_snapshot(con)
        after_daily = daily_kyc(con)
        con.close()

        ivan_after = next(r for r in after.values() if r["account_id"] == IVAN_ACCOUNT)
        failures = []
        if ivan_after["identity_verified_at_utc"] != INJECTED_EVENT_UTC.replace(tzinfo=None):
            failures.append(f"Ivan identity_verified_at_utc = {ivan_after['identity_verified_at_utc']}")
        if (ivan_after["furthest_step_observed"], ivan_after["furthest_step_strict"]) != (3, 3):
            failures.append(f"Ivan steps = {ivan_after['furthest_step_observed']}/{ivan_after['furthest_step_strict']}")
        if ivan_after["kyc_events"] != ivan_before["kyc_events"] + 1:
            failures.append(f"Ivan kyc_events {ivan_before['kyc_events']} -> {ivan_after['kyc_events']}")

        changed = [k for k in before if before[k]["_loaded_at_utc"] != after[k]["_loaded_at_utc"]]
        if changed != [ivan_before["user_sk"]]:
            failures.append(f"rows reloaded: {len(changed)} (expected only Ivan)")
        for k in before:
            if k == ivan_before["user_sk"]:
                continue
            if before[k] != after[k]:
                failures.append(f"untouched person changed: {before[k]['account_id']}")
        if set(after) != set(before):
            failures.append("row set changed")

        cohort = ivan_before["signup_date_pt"]
        if after_daily.get(cohort) != before_daily.get(cohort) + 1:
            failures.append(f"daily KYC count for {cohort}: {before_daily.get(cohort)} -> {after_daily.get(cohort)}")

        print()
        print(
            f"Ivan before: observed {ivan_before['furthest_step_observed']}, "
            f"verified_at {ivan_before['identity_verified_at_utc']}"
        )
        print(
            f"Ivan after:  observed {ivan_after['furthest_step_observed']}, "
            f"verified_at {ivan_after['identity_verified_at_utc']}"
        )
        print(f"rows reloaded by the incremental merge: {len(changed)} of {len(after)}")
        print(f"cohort {cohort} KYC-approved: {before_daily.get(cohort)} -> {after_daily.get(cohort)}")
        if failures:
            print("\nFAIL:")
            for f in failures:
                print("  -", f)
            return 1
        print("\nPASS: late-arriving event processed by the incremental path; only the touched person was recomputed")
        return 0
    finally:
        con = duckdb.connect(str(DB))
        con.execute("delete from analytics.raw_kyc_events where vendor = ?", [INJECTED_ROW_ID])
        con.close()
        dbt("build", "--full-refresh", "--select", "int_funnel__events+", "--exclude", "resource_type:seed")


if __name__ == "__main__":
    sys.exit(main())
