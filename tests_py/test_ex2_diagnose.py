"""Unit tests for the Exercise 2 diagnostic. Small hand-built extracts, one cause per test."""
from __future__ import annotations

import csv
import sys
from datetime import date
from pathlib import Path
from zoneinfo import ZoneInfo

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

from ex2_diagnose import Extract, canon_id, diagnose, duplicate_report, parse_ts, set_report  # noqa: E402

PT = ZoneInfo("America/Los_Angeles")


def write(path: Path, header: list[str], rows: list[list]) -> Path:
    with path.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)
    return path


def test_canon_id_normalises_case_whitespace_and_zero_padding():
    assert canon_id(" acc-1 ") == "ACC-1"
    assert canon_id("000042") == "42"
    assert canon_id("") == ""


def test_parse_ts_handles_iso_z_offsets_and_epochs():
    assert parse_ts("2026-09-14T15:00:00Z").hour == 15
    assert parse_ts("2026-09-14 15:00:00+02:00").utcoffset().total_seconds() == 7200
    assert parse_ts("1789401600").year == 2026
    assert parse_ts("1789401600000").year == 2026
    assert parse_ts("not a date") is None


def test_duplicate_report_separates_exact_rows_from_case_variants(tmp_path):
    p = write(tmp_path / "c.csv", ["account_id", "created_at", "email"], [
        ["ACC-1", "2026-09-14T12:00:00Z", "a@x.com"],
        ["ACC-1", "2026-09-14T12:00:00Z", "a@x.com"],   # exact re-delivery
        ["acc-1", "2026-09-14T12:00:00Z", "a@x.com"],   # case variant
        ["ACC-2", "2026-09-14T13:00:00Z", "b@x.com"],
        ["ACC-2", "2026-09-14T14:00:00Z", "b@x.com"],   # same id, different ts: a real second row
    ])
    d = duplicate_report(Extract.load("C", p))
    assert d["rows"] == 5
    assert d["exact_duplicate_rows"] == 1
    assert d["distinct_rows"] == 4
    assert d["distinct_raw_ids"] == 3
    assert d["distinct_canonical_ids"] == 2
    assert d["case_or_padding_variant_ids"] == 1
    assert d["ids_with_multiple_timestamps"] == 1


def test_set_report_names_users_not_counts(tmp_path):
    a = Extract.load("A", write(tmp_path / "a.csv", ["user_id"], [["1"], ["2"], ["3"]]))
    b = Extract.load("B", write(tmp_path / "b.csv", ["user_id"], [["2"], ["3"], ["4"]]))
    s = set_report([a, b])
    assert s["pairwise"] == {"A&B": 2}
    assert s["only_in"] == {"A": ["1"], "B": ["4"]}


def test_timezone_boundary_is_detected_from_hour_histogram(tmp_path):
    day = date(2026, 9, 14)
    a = write(tmp_path / "a.csv", ["account_id", "created_at_utc", "email"], [
        ["U1", "2026-09-14T03:00:00Z", "u1@ex.com"],   # 20:00 PT Sep 13 -> previous local day
        ["U2", "2026-09-14T15:00:00Z", "u2@ex.com"],
        ["QA1", "2026-09-14T12:00:00Z", "bot@qa.corp.test"],
    ])
    b = write(tmp_path / "b.csv", ["user_id", "verified_at_utc"], [
        ["U2", "2026-09-14T15:05:00Z"],
        ["U3", "2026-09-15T02:00:00Z"],                 # 19:00 PT Sep 14 -> only B has it
    ])
    c = write(tmp_path / "c.csv", ["account_id", "created_at_utc", "email"], [
        ["U1", "2026-09-14T03:00:00Z", "u1@ex.com"],
        ["U2", "2026-09-14T15:00:00Z", "u2@ex.com"],
        ["u2", "2026-09-14T15:00:00Z", "u2@ex.com"],
        ["QA1", "2026-09-14T12:00:00Z", "bot@qa.corp.test"],
    ])
    r = diagnose([a, b, c], day, PT, verified_rate=1.0)
    assert r["timezone"]["System A"]["utc_day_but_previous_local_day"] == ["U1"]
    assert r["hour_histograms_of_one_system_only_users"]["System B"] == {2: 1}
    assert r["qa"]["System A"]["qa_by_email"] == ["QA1"]
    assert r["duplicates"]["System C"]["case_or_padding_variant_ids"] == 1
    # bridge: C 4 rows -> 3 canonical ids; A 3 ids - 1 QA - 1 prev day + 1 evening = 2 people; B has 2.
    assert r["bridge"]["recommended"] == 2
    assert r["bridge"]["residual"] == 0


def test_unexplained_users_show_up_as_nonzero_residual(tmp_path):
    """Honesty check: a user that only System B has, at an hour the time-zone rule cannot explain,
    must surface as a nonzero residual with the id named, not be absorbed into an estimate."""
    day = date(2026, 9, 14)
    a = write(tmp_path / "a.csv", ["account_id", "created_at_utc", "email"], [
        ["U1", "2026-09-14T15:00:00Z", "u1@ex.com"],
        ["U2", "2026-09-14T16:00:00Z", "u2@ex.com"],
        ["U3", "2026-09-14T17:00:00Z", "u3@ex.com"],
        ["U4", "2026-09-14T18:00:00Z", "u4@ex.com"],
    ])
    b = write(tmp_path / "b.csv", ["user_id", "verified_at_utc"], [
        ["U1", "2026-09-14T15:05:00Z"],
        ["U9", "2026-09-15T02:00:00Z"],          # 19:00 PT Sep 14: the evening band, explainable
        ["GHOST", "2026-09-14T15:05:00Z"],       # mid-afternoon: A should have seen this user
    ])
    c = write(tmp_path / "c.csv", ["account_id", "created_at_utc", "email"], [
        ["U1", "2026-09-14T15:00:00Z", "u1@ex.com"],
        ["U2", "2026-09-14T16:00:00Z", "u2@ex.com"],
        ["U3", "2026-09-14T17:00:00Z", "u3@ex.com"],
        ["U4", "2026-09-14T18:00:00Z", "u4@ex.com"],
    ])
    r = diagnose([a, b, c], day, PT, verified_rate=1.0)
    assert sorted(r["sets"]["only_in"]["System B"]) == ["GHOST", "U9"]
    bridge = r["bridge"]
    assert bridge["evening_only_ids"] == ["U9"]
    assert bridge["unexplained_ids"] == ["GHOST"]
    assert bridge["residual"] == 1
    assert bridge["recommended"] == 5          # 4 in A + 1 explainable evening user; GHOST is not added
