#!/usr/bin/env python3
"""Run the generic diagnostic (ex2_diagnose.py) against the generated fixtures and assert that it
recovers every planted cause without having been told any of them. This is the test of the
method; the method itself lives in ex2_diagnose.py and works on any three extracts.

Expected bridge: 57,000 -> 52,000 -> 50,007 (recommended) -> 45,003, residual 0.
"""
from __future__ import annotations

import json
from datetime import date
from pathlib import Path
from zoneinfo import ZoneInfo

from ex2_diagnose import diagnose, print_report

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data" / "ex2"


def main() -> None:
    paths = [DATA / "system_a.csv", DATA / "system_b.csv", DATA / "system_c.csv"]
    report = diagnose(paths, date(2026, 9, 14), ZoneInfo("America/Los_Angeles"), verified_rate=0.90)
    print_report(report)
    (DATA / "bridge.json").write_text(json.dumps(report["bridge"], indent=2, default=str) + "\n")

    dup_c = report["duplicates"]["System C"]
    assert dup_c["rows"] == 57_000
    assert dup_c["exact_duplicate_rows"] == 4_000, dup_c
    assert dup_c["distinct_rows"] - dup_c["distinct_canonical_ids"] == 1_000, dup_c
    assert report["sets"]["distinct"] == {"System A": 52_000, "System B": 45_003, "System C": 52_000}
    assert len(report["qa"]["System A"]["qa_by_email"]) == 1_000
    assert len(report["timezone"]["System A"]["utc_day_but_previous_local_day"]) == 4_500
    assert len(report["sets"]["only_in"]["System B"]) == 3_156
    # The one-system-only users cluster in UTC hours 0-6: Pacific evening, not data loss.
    hist = report["hour_histograms_of_one_system_only_users"]["System B"]
    assert set(hist) <= set(range(0, 7)), hist
    assert report["bridge"]["recommended"] == 50_007
    assert report["bridge"]["residual"] == 0
    print("\nPASS: diagnostic recovered every planted cause; residual 0")


if __name__ == "__main__":
    main()
