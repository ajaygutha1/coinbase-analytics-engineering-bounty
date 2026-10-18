#!/usr/bin/env python3
"""Exercise 2: find out WHERE three signup extracts diverge, without being told the answer.

    python scripts/ex2_diagnose.py data/ex2/system_a.csv data/ex2/system_b.csv data/ex2/system_c.csv \
        --day 2024-01-15 --tz America/Los_Angeles [--json out.json]

The script never assumes a cause. It runs the checks in the order you would with two hours on the
clock, prints what it finds, and ends with a bridge from the largest number to the smallest and
the residual it could not explain. Every step is a plain function so it can be unit-tested.

Order of investigation (each one names a concrete set of users, not just a count):
  1. Row-level duplicates in each file, starting with System C: exact duplicate rows, then
     duplicate ids after canonicalisation (trim / case / zero-padding), then ids that repeat with
     different timestamps (true multi-row users vs re-deliveries).
  2. Set algebra between systems on canonical ids: pairwise intersections, one-system-only users.
  3. Time-zone boundary: hour-of-day histogram (UTC) of the users that only one system has.
     A wall at 07:00Z / 08:00Z is Pacific midnight, not data loss.
  4. Population differences: test / QA accounts by email domain or id pattern.
  5. Definition differences: a system that only has users present in another system's
     "verified" / lifecycle set is counting a different event.
  6. Bridge and residual.

Column detection is heuristic (id / timestamp / email / flag columns found by name), so the same
script runs on extracts with different headers. Everything else is exact.
"""
from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from zoneinfo import ZoneInfo

ID_HINTS = ("account_id", "user_id", "customer_id", "uid", "id")
TS_HINTS = ("created_at", "signup_ts", "verified_at", "event_ts", "timestamp", "_at", "_ts", "date")
EMAIL_HINTS = ("email",)
VERIFIED_HINTS = ("verified", "email_verified", "is_verified")
QA_PATTERNS = (r"@qa\.", r"@test\.", r"\.test$", r"\+test@", r"^qa[_-]", r"^test[_-]")


# --------------------------------------------------------------------------- helpers
def canon_id(value: str) -> str:
    """Canonical spelling of an id: trimmed, upper-cased, numeric zero-padding stripped."""
    v = (value or "").strip().upper()
    if v.isdigit():
        v = str(int(v))
    return v


def parse_ts(value: str) -> datetime | None:
    v = (value or "").strip()
    if not v:
        return None
    if v.isdigit():
        n = int(v)
        return datetime.fromtimestamp(n / 1000 if n > 1e11 else n, tz=UTC)
    try:
        dt = datetime.fromisoformat(v.replace("Z", "+00:00").replace(" ", "T"))
    except ValueError:
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=UTC)


def pick(header: list[str], hints: tuple[str, ...]) -> str | None:
    lowered = {h.lower(): h for h in header}
    for hint in hints:
        for low, orig in lowered.items():
            if low == hint or low.endswith(hint) or hint in low:
                return orig
    return None


@dataclass
class Extract:
    name: str
    path: Path
    rows: list[dict[str, str]]
    id_col: str
    ts_col: str | None
    email_col: str | None
    verified_col: str | None
    notes: list[str] = field(default_factory=list)

    @classmethod
    def load(cls, name: str, path: Path) -> Extract:
        with path.open(newline="") as f:
            reader = csv.DictReader(f)
            header = reader.fieldnames or []
            rows = list(reader)
        id_col = pick(header, ID_HINTS)
        if id_col is None:
            sys.exit(f"{name}: could not find an id column in {header}")
        return cls(
            name, path, rows, id_col,
            pick(header, TS_HINTS), pick(header, EMAIL_HINTS), pick(header, VERIFIED_HINTS),
        )

    def raw_ids(self) -> list[str]:
        return [r[self.id_col] for r in self.rows]

    def canon_ids(self) -> set[str]:
        return {canon_id(r[self.id_col]) for r in self.rows}

    def ts_by_id(self) -> dict[str, datetime]:
        out: dict[str, datetime] = {}
        if not self.ts_col:
            return out
        for r in self.rows:
            ts = parse_ts(r.get(self.ts_col, ""))
            cid = canon_id(r[self.id_col])
            if ts and (cid not in out or ts < out[cid]):
                out[cid] = ts
        return out

    def email_by_id(self) -> dict[str, str]:
        if not self.email_col:
            return {}
        return {canon_id(r[self.id_col]): (r.get(self.email_col) or "").strip().lower() for r in self.rows}


# --------------------------------------------------------------------------- checks
def duplicate_report(x: Extract) -> dict:
    """Step 1: three flavours of duplicate, each a separate number because each has a different fix."""
    raw = x.raw_ids()
    exact_rows = Counter(tuple(sorted(r.items())) for r in x.rows)
    exact_duplicate_rows = sum(c - 1 for c in exact_rows.values())

    distinct_raw_rows = len(exact_rows)
    distinct_raw_ids = len(set(raw))
    distinct_canon_ids = len(x.canon_ids())

    # ids that survive exact-row dedupe but collapse after canonicalisation
    variant_groups = defaultdict(set)
    for rid in set(raw):
        variant_groups[canon_id(rid)].add(rid)
    case_variant_ids = {k: sorted(v) for k, v in variant_groups.items() if len(v) > 1}

    # same canonical id, different timestamps (genuine repeated events, not re-deliveries)
    multi_ts = 0
    if x.ts_col:
        ts_sets = defaultdict(set)
        for r in x.rows:
            ts_sets[canon_id(r[x.id_col])].add(r.get(x.ts_col, ""))
        multi_ts = sum(1 for v in ts_sets.values() if len(v) > 1)

    return {
        "rows": len(raw),
        "exact_duplicate_rows": exact_duplicate_rows,
        "distinct_rows": distinct_raw_rows,
        "distinct_raw_ids": distinct_raw_ids,
        "distinct_canonical_ids": distinct_canon_ids,
        "case_or_padding_variant_ids": len(case_variant_ids),
        "example_variants": dict(list(case_variant_ids.items())[:3]),
        "ids_with_multiple_timestamps": multi_ts,
    }


def set_report(extracts: list[Extract]) -> dict:
    """Step 2: compare sets, not counts. A count can match by coincidence."""
    ids = {x.name: x.canon_ids() for x in extracts}
    names = [x.name for x in extracts]
    out: dict = {"distinct": {n: len(ids[n]) for n in names}, "pairwise": {}, "only_in": {}}
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            out["pairwise"][f"{a}&{b}"] = len(ids[a] & ids[b])
    everything = set().union(*ids.values())
    out["union"] = len(everything)
    out["in_all"] = len(set.intersection(*ids.values()))
    for n in names:
        others = set().union(*(ids[m] for m in names if m != n))
        out["only_in"][n] = sorted(ids[n] - others)
    return out


def hour_histogram(x: Extract, id_subset: set[str]) -> dict[int, int]:
    """Step 3: UTC hour-of-day of a subset of users. A cliff at a fixed hour is a time-zone rule."""
    ts = x.ts_by_id()
    return dict(sorted(Counter(ts[i].astimezone(UTC).hour for i in id_subset if i in ts).items()))


def timezone_report(x: Extract, day: datetime.date, tz: ZoneInfo) -> dict:
    """How many of this extract's users fall on the reporting day in UTC vs in the reporting zone."""
    ts = x.ts_by_id()
    utc_day = {i for i, t in ts.items() if t.astimezone(UTC).date() == day}
    local_day = {i for i, t in ts.items() if t.astimezone(tz).date() == day}
    return {
        "users_with_timestamp": len(ts),
        "on_day_utc": len(utc_day),
        "on_day_local": len(local_day),
        "utc_day_but_previous_local_day": sorted(i for i in utc_day if ts[i].astimezone(tz).date() < day),
        "local_day_but_next_utc_day": sorted(i for i in local_day if ts[i].astimezone(UTC).date() > day),
    }


def qa_report(x: Extract) -> dict:
    """Step 4: population differences you can prove from the row itself."""
    emails = x.email_by_id()
    qa = sorted(i for i, e in emails.items() if any(re.search(p, e) for p in QA_PATTERNS))
    qa_ids = sorted(i for i in x.canon_ids() if re.match(r"^(QA|TEST)[-_]", i))
    domains = Counter(e.split("@")[-1] for e in emails.values() if "@" in e)
    return {"qa_by_email": qa, "qa_by_id_pattern": qa_ids, "top_domains": domains.most_common(5)}


def definition_report(extracts: list[Extract]) -> dict:
    """Step 5: does a system carry a flag that explains its own count? (verified-only etc.)"""
    out = {}
    for x in extracts:
        if x.verified_col:
            vals = Counter((r.get(x.verified_col) or "").strip().lower() for r in x.rows)
            out[x.name] = {"flag_column": x.verified_col, "values": dict(vals)}
        if x.ts_col and re.search(r"verif", x.ts_col, re.I):
            out[x.name] = {"timestamp_column": x.ts_col, "meaning": "rows exist only for verified users"}
    return out


# --------------------------------------------------------------------------- bridge
def build_bridge(extracts: list[Extract], day: datetime.date, tz: ZoneInfo, verified_rate: float) -> dict:
    """Step 6: from the largest number to the smallest, each line either exact or labelled estimate."""
    dup = {x.name: duplicate_report(x) for x in extracts}
    sets = set_report(extracts)
    largest = max(extracts, key=lambda x: len(x.rows))
    smallest = min(extracts, key=lambda x: len(x.canon_ids()))
    middle = [x for x in extracts if x not in (largest, smallest)]
    base = middle[0] if middle else largest

    lines: list[tuple[str, int, str]] = []
    running = dup[largest.name]["rows"]
    lines.append((f"{largest.name} raw rows", running, "exact"))
    running -= dup[largest.name]["exact_duplicate_rows"]
    lines.append((f"- exact duplicate rows in {largest.name}", -dup[largest.name]["exact_duplicate_rows"], "exact"))
    variants = dup[largest.name]["distinct_rows"] - dup[largest.name]["distinct_canonical_ids"]
    running -= variants
    lines.append((f"- case/padding variant ids in {largest.name}", -variants, "exact"))
    lines.append((f"= {largest.name} distinct canonical ids", running, "exact"))

    base_ids = base.canon_ids()
    qa = set(qa_report(base)["qa_by_email"]) | set(qa_report(base)["qa_by_id_pattern"])
    tzr = timezone_report(base, day, tz)
    prev_day = set(tzr["utc_day_but_previous_local_day"]) - qa
    running_people = len(base_ids) - len(qa) - len(prev_day)
    lines.append((f"- test / QA accounts in {base.name}", -len(qa), "exact"))
    lines.append((f"- previous {tz.key} day (UTC-day spillover)", -len(prev_day), "exact"))

    # Users the smallest (verified-only) system has that the base does not. Only the ones whose
    # own timestamp falls in the reporting day locally but the NEXT day in UTC are explained by the
    # base extract cutting off at 24:00Z; we observe just the verified ones, so gross those up.
    # Anything else that only the smallest system has is NOT explained and becomes the residual.
    small_only = set(sets["only_in"].get(smallest.name, []))
    small_tz = timezone_report(smallest, day, tz) if smallest.ts_col else {"local_day_but_next_utc_day": []}
    evening = small_only & set(small_tz["local_day_but_next_utc_day"])
    unexplained = small_only - evening
    est_evening = round(len(evening) / verified_rate) if evening else 0
    if evening:
        label = (f"+ {tz.key} evening after 24:00Z (observed {len(evening)} verified in "
                 f"{smallest.name}, grossed up at {verified_rate:.0%})")
        lines.append((label, est_evening, "ESTIMATE"))
        running_people += est_evening
    lines.append((f"= distinct production people on the {tz.key} day", running_people, "recommended"))

    # The smallest system's count is explained by the recommended number minus the people it does
    # not carry (its definition), plus any users it has that nothing above accounts for.
    unverified = running_people + len(unexplained) - len(smallest.canon_ids())
    lines.append((f"- signed up but not in {smallest.name} (definition: verified-only)", -unverified, "derived"))
    if unexplained:
        label = f"+ users only {smallest.name} has that no identified cause explains"
        lines.append((label, len(unexplained), "UNEXPLAINED"))
    lines.append((f"= {smallest.name} distinct ids", len(smallest.canon_ids()), "exact"))
    return {"lines": lines, "residual": len(unexplained), "recommended": running_people,
            "qa_ids": sorted(qa)[:5], "previous_day_ids": sorted(prev_day)[:5],
            "evening_only_ids": sorted(evening)[:5], "unexplained_ids": sorted(unexplained)[:20]}


# --------------------------------------------------------------------------- main
def diagnose(paths: list[Path], day: datetime.date, tz: ZoneInfo, verified_rate: float) -> dict:
    extracts = [Extract.load(f"System {chr(65 + i)}", p) for i, p in enumerate(paths)]
    report = {
        "columns": {x.name: {"id": x.id_col, "timestamp": x.ts_col, "email": x.email_col, "verified": x.verified_col}
                    for x in extracts},
        "duplicates": {x.name: duplicate_report(x) for x in extracts},
        "sets": set_report(extracts),
        "timezone": {x.name: timezone_report(x, day, tz) for x in extracts if x.ts_col},
        "qa": {x.name: qa_report(x) for x in extracts},
        "definitions": definition_report(extracts),
    }
    only = report["sets"]["only_in"]
    report["hour_histograms_of_one_system_only_users"] = {
        x.name: hour_histogram(x, set(only[x.name])) for x in extracts if x.ts_col and only[x.name]
    }
    report["bridge"] = build_bridge(extracts, day, tz, verified_rate)
    return report


def print_report(r: dict) -> None:
    print("\n== 1. Duplicates (start with the largest system) ==")
    for name, d in r["duplicates"].items():
        print(f"{name}: rows={d['rows']:,} exact_dup_rows={d['exact_duplicate_rows']:,} "
              f"distinct_raw_ids={d['distinct_raw_ids']:,} distinct_canonical_ids={d['distinct_canonical_ids']:,} "
              f"variant_ids={d['case_or_padding_variant_ids']:,} multi_ts_ids={d['ids_with_multiple_timestamps']:,}")
        if d["example_variants"]:
            print(f"   e.g. {d['example_variants']}")
    print("\n== 2. Sets, not counts ==")
    s = r["sets"]
    print(f"distinct: {s['distinct']}  pairwise: {s['pairwise']}  in_all={s['in_all']:,} union={s['union']:,}")
    for name, ids in s["only_in"].items():
        print(f"only in {name}: {len(ids):,}  e.g. {ids[:3]}")
    print("\n== 3. UTC hour-of-day of one-system-only users (a cliff = a time-zone rule) ==")
    for name, h in r["hour_histograms_of_one_system_only_users"].items():
        print(f"{name}: {h}")
    for name, t in r["timezone"].items():
        print(f"{name}: on_day_utc={t['on_day_utc']:,} on_day_local={t['on_day_local']:,} "
              f"utc_day_but_prev_local={len(t['utc_day_but_previous_local_day']):,} "
              f"local_day_but_next_utc={len(t['local_day_but_next_utc_day']):,}")
    print("\n== 4. Population: test / QA accounts ==")
    for name, q in r["qa"].items():
        print(f"{name}: qa_by_email={len(q['qa_by_email']):,} qa_by_id={len(q['qa_by_id_pattern']):,} "
              f"domains={q['top_domains'][:3]}")
    print("\n== 5. Definition signals ==")
    print(r["definitions"] or "no verified/lifecycle flags found in headers")
    print("\n== 6. Bridge ==")
    for label, value, kind in r["bridge"]["lines"]:
        print(f"{label:<75} {value:>+10,}   {kind}")
    print(f"{'Residual (unexplained)':<75} {r['bridge']['residual']:>+10,}")
    print(f"\nRecommended number: {r['bridge']['recommended']:,} (see the ESTIMATE line before publishing)")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("csv", nargs=3, type=Path, help="three extracts: System A, System B, System C")
    ap.add_argument("--day", required=True, help="reporting day, YYYY-MM-DD")
    ap.add_argument("--tz", default="America/Los_Angeles", help="reporting time zone")
    ap.add_argument("--verified-rate", type=float, default=0.90,
                    help="assumed verification rate for the evening gross-up")
    ap.add_argument("--json", type=Path, help="write the full report here")
    args = ap.parse_args(argv)
    report = diagnose(args.csv, datetime.fromisoformat(args.day).date(), ZoneInfo(args.tz), args.verified_rate)
    print_report(report)
    if args.json:
        args.json.write_text(json.dumps(report, indent=2, default=str) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
