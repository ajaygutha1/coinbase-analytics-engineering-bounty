"""First pass on three signup extracts: duplicates in C, set differences by id, profile of A-only users.

Usage: python scripts/ex2_first_pass.py system_a.csv system_b.csv system_c.csv
The full blind diagnostic and bridge live in ex2_diagnose.py."""
import csv
import sys
from collections import Counter
from datetime import datetime
from zoneinfo import ZoneInfo


def load(path):
    with open(path, newline="") as f:
        return list(csv.DictReader(f))

def canon(row):  # one id convention across systems: trim, case, zero-padding
    raw = (row.get("account_id") or row.get("user_id") or "").strip().upper()
    prefix, _, num = raw.rpartition("-")
    return f"{prefix}-{int(num):05d}" if num.isdigit() else raw

a, b, c = (load(p) for p in sys.argv[1:4])

# 1. System C duplicates: exact re-deliveries vs ids that only collide after normalising
distinct_rows = {tuple(r.values()) for r in c}
people_c = {canon(r) for r in c}
print(f"C rows {len(c):,}: exact dupes {len(c) - len(distinct_rows):,}, "
      f"id variants {len(distinct_rows) - len(people_c):,}, distinct people {len(people_c):,}")

# 2. Where the systems diverge, by id (counts can match by coincidence; ids cannot)
A, B = ({canon(r) for r in s} for s in (a, b))
for name, s in {"C-A": people_c - A, "A-C": A - people_c, "A-B": A - B, "B-A": B - A}.items():
    print(f"{name}: {len(s):,}")

# 3. Profile A's users missing from B: test accounts? a timezone boundary? Each is a hypothesis to confirm
only_a = A - B  # build the set difference once, not once per row
a_only = [r for r in a if canon(r) in only_a]
pt = ZoneInfo("America/Los_Angeles")
print("test accounts:", sum(r["email"].endswith(".test") for r in a_only))
print("A-only by Pacific day:", dict(Counter(
    datetime.fromisoformat(r["created_at_utc"]).astimezone(pt).date() for r in a_only)))
