#!/usr/bin/env python3
"""Independent Python oracle for the planted funnel cases (no dbt/DuckDB required)."""
from __future__ import annotations

import csv
from collections import defaultdict
from datetime import UTC, datetime
from decimal import Decimal, InvalidOperation
from hashlib import md5
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
SEEDS = ROOT / "seeds"
PT = ZoneInfo("America/Los_Angeles")
ZERO = "0x0000000000000000000000000000000000000000"
MIN_USD = Decimal("1")


def read(name: str):
    with (SEEDS / name).open(newline="") as f:
        return list(csv.DictReader(f))


def iso(s: str) -> datetime:
    return datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(UTC)


def epoch(v: str) -> datetime:
    x = int(v)
    if abs(x) >= 100_000_000_000:
        x /= 1000
    return datetime.fromtimestamp(x, UTC)


def local_pt(s: str) -> datetime:
    # Fixture dates avoid the ambiguous DST fall-back hour. Production SQL flags that hour.
    return datetime.fromisoformat(s).replace(tzinfo=PT).astimezone(UTC)


def user_key(canonical_account: str) -> str:
    return md5(canonical_account.encode()).hexdigest()


def main() -> None:
    xref = read("raw_identity_user_xref.csv")
    by_account = {r["account_id"].strip().upper(): r for r in xref}
    acct_map: dict[str, tuple[str, str, bool]] = {}
    legacy_map: dict[str, tuple[str, str, bool]] = {}
    for r in xref:
        account = r["account_id"].strip().upper()
        merged = r["merged_into_account_id"].strip().upper()
        canonical = merged or account
        survivor = by_account.get(canonical, r)
        is_test = r["is_test_account"].lower() == "true" or survivor["is_test_account"].lower() == "true"
        payload = (user_key(canonical), canonical, is_test)
        acct_map[account] = payload
        legacy_map[str(int(r["legacy_user_id"]))] = payload

    events: list[dict] = []

    # Auth: exact event-id redeliveries keep earliest ingestion.
    best_auth: dict[str, dict] = {}
    for r in read("raw_auth_events.csv"):
        eid = r["event_id"]
        if eid not in best_auth or iso(r["ingested_at"]) < iso(best_auth[eid]["ingested_at"]):
            best_auth[eid] = r
    for r in best_auth.values():
        account = r["account_id"].strip().upper()
        ident = acct_map.get(account)
        events.append({
            "key": "auth|" + r["event_id"],
            "user": ident[0] if ident else None,
            "account": ident[1] if ident else None,
            "test": ident[2] if ident else False,
            "step": "signed_up" if r["event_name"].lower() == "account_created" else "email_verified",
            "ordinal": 1 if r["event_name"].lower() == "account_created" else 2,
            "at": iso(r["event_ts"]), "success": True, "negative": False, "revoked": False,
        })

    # KYC: retries/status history are real rows, not duplicates.
    for r in read("raw_kyc_events.csv"):
        legacy = str(int(r["customer_ref"]))
        ident = legacy_map.get(legacy)
        status = r["status"].lower()
        at = epoch(r["updated_at_ms"])
        events.append({
            "key": f"kyc|{r['case_id']}|{r['attempt_no']}|{status}|{at:%Y%m%d%H%M%S}",
            "user": ident[0] if ident else None,
            "account": ident[1] if ident else None,
            "test": ident[2] if ident else False,
            "step": "identity_verified", "ordinal": 3, "at": at,
            "success": status == "approved", "negative": status in {"rejected", "revoked"},
            "revoked": status == "revoked",
        })

    # Ledger: txn-id redelivery first, then semantic natural-key restatement.
    status_map = {int(r["status_code"]): r["is_settled"].lower() == "true" for r in read("ledger_status_codes.csv")}
    status_name = {int(r["status_code"]): r["status_name"] for r in read("ledger_status_codes.csv")}
    by_txn: dict[str, dict] = {}
    for r in read("raw_ledger_transactions.csv"):
        tid = r["txn_id"]
        if tid not in by_txn or iso(r["ingested_at"]) > iso(by_txn[tid]["ingested_at"]):
            by_txn[tid] = r
    semantic: dict[str, dict] = {}
    for r in by_txn.values():
        if r["tx_hash"] and r["chain_id"] and r["log_index"]:
            k = f"{r['chain_id']}:{r['tx_hash'].lower()}:{int(r['log_index'])}"
        else:
            k = r["txn_id"]
        if k not in semantic or iso(r["ingested_at"]) > iso(semantic[k]["ingested_at"]):
            semantic[k] = r

    deposit_event_counts = defaultdict(int)
    for k, r in semantic.items():
        legacy = str(int(r["user_id"]))
        ident = legacy_map.get(legacy)
        typ = r["txn_type"].lower()
        if typ not in {"deposit", "trade"}:
            continue
        settled = status_map.get(int(r["status_code"]), False)
        try:
            usd = Decimal(r["usd_notional"]) if r["usd_notional"] else None
        except InvalidOperation:
            usd = None
        zero = r["from_address"].lower() == ZERO if r["from_address"] else False
        success = settled if typ == "trade" else (settled and usd is not None and usd >= MIN_USD and not zero)
        name = status_name.get(int(r["status_code"]), "unknown")
        at = local_pt(r["settled_at_local"] or r["created_at_local"])
        e = {
            "key": "ledger|" + k, "source_id": r["txn_id"],
            "user": ident[0] if ident else None, "account": ident[1] if ident else None,
            "test": ident[2] if ident else False,
            "step": "first_deposit" if typ == "deposit" else "first_trade",
            "ordinal": 4 if typ == "deposit" else 5, "at": at,
            "success": success, "negative": name in {"failed", "reversed"}, "revoked": False,
            "usd": usd,
        }
        events.append(e)
        if typ == "deposit" and ident:
            deposit_event_counts[ident[1]] += 1

    unresolved = [e for e in events if e["user"] is None]
    assert len(unresolved) == 1 and unresolved[0]["step"] == "identity_verified"

    valid = [e for e in events if e["user"] is not None and not e["test"]]
    by_user_step = defaultdict(list)
    for e in valid:
        by_user_step[(e["user"], e["step"])].append(e)

    users: dict[str, dict] = defaultdict(dict)
    for (u, step), rows in by_user_step.items():
        successes = sorted((e for e in rows if e["success"]), key=lambda e: (e["at"], e["key"]))
        users[u][step] = successes[0] if successes else None
        users[u][step + "_negative"] = sum(e["negative"] for e in rows)
        users[u][step + "_revoked"] = sum(e["revoked"] for e in rows)

    account_to_user = {canonical: u for u, canonical, test in acct_map.values() if not test}

    def ev(account: str, step: str):
        return users[account_to_user[account]].get(step)

    # Planted correctness cases.
    assert len(users) == 8
    assert ev("ACC-0001", "first_deposit")["source_id"] == "l1-new"  # re-org replacement
    assert deposit_event_counts["ACC-0003"] == 2  # two log indexes, duplicate txn_id removed
    assert ev("ACC-0004", "first_deposit")["source_id"] == "l4-dep"  # zero mint ignored
    assert users[account_to_user["ACC-0002"]]["identity_verified_negative"] == 1  # retry audited
    assert users[account_to_user["ACC-0006"]]["identity_verified_revoked"] == 1  # revoke retained
    assert ev("ACC-0011", "signed_up")["at"] == iso("2026-09-13T18:00:00Z")  # merged person keeps older signup
    assert ev("ACC-0003", "signed_up")["at"].astimezone(PT).date().isoformat() == "2026-09-13"  # UTC/PT boundary
    assert account_to_user.get("ACC-QA01") is None  # test person is not in trusted population mapping

    # Grace: trade arrives before deposit, so observed reaches 5 while strict stops at 4.
    g = users[account_to_user["ACC-0005"]]
    step_order = ["signed_up", "email_verified", "identity_verified", "first_deposit", "first_trade"]
    ordinal = {name: i for i, name in enumerate(step_order, 1)}
    observed = max(ordinal[s] for s in step_order if g.get(s))
    ordered = [g.get(s) for s in ["signed_up", "email_verified", "identity_verified", "first_deposit", "first_trade"]]
    strict = 0
    prev = None
    for idx, item in enumerate(ordered, 1):
        if item is None or (prev is not None and item["at"] < prev):
            break
        strict = idx
        prev = item["at"]
    assert observed == 5 and strict == 4

    print("PASS: independent fixture oracle")
    print("  trusted people: 8")
    print("  re-org replacement, batched logs, zero mint, KYC retry/revocation, merge, PT boundary: verified")
    print("  Grace observed/strict: 5/4")
    print("  unresolved identity rows retained upstream: 1")


if __name__ == "__main__":
    main()
