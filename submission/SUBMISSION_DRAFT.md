# Exercise 1 — Design the data model

*In short: one trustworthy row per person, with every odd case flagged instead of hidden.*

**Implementation:** https://github.com/ajaygutha1/coinbase-analytics-engineering-bounty — a runnable dbt project on DuckDB. Every pitfall below is a planted seed row and a passing test: 8 unit, 36 singular and 211 schema tests, enforced contracts on every mart, green CI with a lint gate.

## What I noticed

I would fix the grain first: **one row per person**, not per event or account. Otherwise every consumer rediscovers merges, retries and duplicates, and that is how the later exercises happen.

```text
Assumed sources (three event tables + the crosswalk that lets them join)
1) auth_events:         account_id (UUID, mixed case), event_id, event_name, ISO-8601 Z event_ts, ingested_at
2) kyc_events:          legacy customer_ref (zero-padded), case_id/attempt_no, status, epoch sec OR ms, ingested_at
3) ledger_transactions: legacy user_id, txn_id, txn_type/status_code, naive PACIFIC created/settled time,
                        chain_id/tx_hash/log_index, amount/usd_notional (strings), ingested_at
4) identity_user_xref:  account_id <-> legacy_user_id, merge pointer, is_test_account

Business rules
- Store UTC; report Pacific calendar days.
- A step advances only on terminal success: created, email verified, KYC approved, deposit settled, trade filled.
- First deposit must be >= a configurable USD threshold (default $1); test accounts excluded from marts only.
```

## What I would build

```text
stg_auth__events ───────────┐
stg_kyc__events ────────────┤
stg_ledger__transactions ───┼─> int_identity__resolved   one row per account AND per legacy id -> user_sk
stg_identity__user_xref ────┘          │
                                       ▼
                            int_funnel__events        one row per semantic event; flags, never deletes
                                    ▼
                            int_funnel__user_steps    one row per person x step; first terminal success
                                    ▼
                           fct_onboarding_funnel      one row per PERSON, enforced contract
                              ├───────────┬─────────────────────┐
                 fct_onboarding_funnel_daily   rpt_signup_definition_bridge   rpt_funnel_data_quality
```

Staging only normalizes. Identity resolution produces the only key allowed downstream. The event layer collapses retries to the first terminal success per person × step; the mart is a boring pivot.

## Keys

Identity links come only from the crosswalk and its merge pointers, never from fuzzy matching on email or name. Wrongly merging two people's KYC records is a compliance error; an unlinked id is a visible warning, so unresolved ids are counted, not guessed. `user_sk` is a hash of the canonical account after following merge pointers, so a re-registered and merged person is one row that keeps the older signup. On-chain deposits are keyed by `(chain_id, tx_hash, log_index)`, never `tx_hash` alone: batched transfers stay distinct and a re-org restatement updates the same event instead of adding a second deposit. Raw crypto amounts stay strings beside a safe fixed-precision parse; an unparseable notional never satisfies the threshold.

## Missing and out-of-order events

I never impute a missing step or drop a person for being out of order. The mart carries two readings:

```sql
furthest_step_observed = highest terminal success ever seen                 -- reporting default
furthest_step_strict   = walk signup→email→KYC→deposit→trade; stop at the    -- always <= observed
                         first step missing or earlier than its predecessor
has_sequence_anomaly   = observed <> strict
data_quality_flags     = 'trade_before_deposit|kyc_revoked_after_approval|late_arriving_event|...'
```

Incrementals watermark on **ingestion time** with a three-day lookback, so a Monday KYC approval landing Thursday still updates Monday's cohort.

## Data quality checks

```yaml
# grain and keys           unique + not_null on user_sk; crosswalk unique on BOTH account_id and legacy_user_id
# privacy and maturity     no email/phone/name columns in any mart; 7-day rates count only cohorts old enough to finish
# closed enums, two-valued flags   accepted_values on status names, rails, is_terminal_success (true/false, never null)
# reconciliation           people in the mart = eligible people in the event layer  (catches silent row loss)
# business invariants      strict <= observed; funnel counts monotonic; no future events; PT and UTC dates differ <= 1 day
# unit tests (fixture rows) four rows sharing a tx_hash; epoch seconds vs ms; 39-digit amount; zero address;
#                          DST fall-back hour and spring-forward gap; 06:58Z lands on the previous PT day
# contract                 every mart column's name and type enforced at build time
# warn-level               unresolved identities are counted and kept, never dropped silently
# freshness SLAs           per source; a stale KYC feed is an incident, not a conversion drop
```

## What I would tell the PM

"The default dashboard uses observed completion, person grain, Pacific cohort day. Strict is for sequence-sensitive questions, and when they differ the table says which users and why."

# Exercise 2 — The data doesn't add up

*In short: the three counts measure different things; a script shows which users sit behind each gap. Numbers below come from synthetic extracts I generated with planted causes, so the method is the point; real causes would be whatever the script finds.*

## What I noticed

C minus A is 5K, and C is the event stream with duplicates, so "C minus duplicates equals A" is the first hypothesis. The 7K from A to B is a definition gap. I would ask what each counts: rows or people, UTC or Pacific day, test or production, created or verified.

## What I would do

Duplicate ids in System C first, then set differences by id, then a profile of users only one system has:

```python
# scripts/ex2_first_pass.py: the first twenty minutes, tested on the fixtures. The full blind
# diagnostic, hour histogram and bridge builder are scripts/ex2_diagnose.py.
import csv, sys
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
```

Timebox: 0–20 min duplicates and set differences; 20–60 profiles of one-system-only users; 60–90 confirm definitions with owners; 90–120 the PM note.

```text
System C raw rows                                        57,000   exact
- exact re-delivered rows                                 4,000   exact
- case-variant duplicate ids                              1,000   exact
= System A distinct accounts, UTC day                    52,000   exact
- test / QA accounts                                      1,000   exact
- 00:00–06:59Z = previous Pacific day                     4,500   exact
+ Pacific evening after 24:00Z                            3,507   ESTIMATE (3,156 verified seen in B, grossed up at 90%)
= distinct production people, Pacific day                50,007   <- recommended (49,800–50,200 if the gross-up is 85–95%)
- signed up but not email-verified                        5,004   REMAINDER (derived, not counted by id)
= System B verified-only                                 45,003   exact
Residual (users no identified cause explains, by id)          0
```

*Daily signups = distinct canonical, non-test people whose first account-created success falls on the Pacific calendar day.*

## What I would flag

System C is an event stream and always reads high; B's "signup" is verified-only, a different metric. The UTC-day boundary moves roughly 8% of a day's signups, so UTC-day history is shifted. The evening line is an estimate because A's extract stops at 24:00Z.

## What I would tell the PM

"Use 50,007 (give or take 200) with the definition in the footnote. Every line is counted by id except the evening estimate and the verified-only remainder; if you'd rather not publish an estimate, the exact alternative is 46,500 'through 5 pm PT'. Then let's persist the bridge so next week this is a query, not an afternoon." (Full memo: `docs/EXERCISE2_PM_MEMO.md`.)

# Exercise 3 — The inherited pipeline

*In short: ship the country cut on today's logic so no number moves, show the corrected version beside it, and switch once the definition is agreed.*

## What I flag, and why

`FROM users u, trades t, devices d` joined on `user_id` turns one trader into N rows, so `completed_trades` is multiplied by each user's active-device count while `COUNT(DISTINCT)` hides it. The status filter lives only inside the `SUM`, so `active_traders` counts any trader, failed or cancelled included, while `completed_trades` counts completed ones: two meanings of "trader". The snippet already groups by country, so the cut is easy; the risk is that it uses each user's current country, as it does the device flag, so reruns change history. Also: a hard-coded, timezone-less week; magic status codes; an inner join dropping traders with no active device; no tests, no owner.

## How I would deliver the country cut without moving the number

The country cut ships on legacy-equivalent logic, so the countries add up to the headline everyone already uses. Beside it, as a labelled column, goes the corrected v2, built as one named CTE per flag. Parity is proven per country before anything ships: the refactor may differ from the legacy output in exactly two explained ways, `active_traders` by the failed-only users and `completed_trades` by the measured device multiplier. Anything else is a changed rule, and v2 waits. A test fails on any unmapped status code, which would silently shrink the metric. Country rows must add back to the global total, and users with no country get an explicit UNKNOWN row. A walk from completed trades to the dashboard (35 − 1 + 7 = 41) shows the defects partly cancel, hence the plausible total.

```sql
-- v2: the labelled column beside the legacy cut, not the version I ship first
with params as (            -- F2: typed window; legacy bounds kept for parity (a PT week is a v2 decision)
  select timestamp '2024-01-01 00:00' as week_start_utc, timestamp '2024-01-08 00:00' as week_end_utc
), completed_trades as (    -- F3 + F6: decoded status, filtered in the WHERE
  select t.user_id, t.trade_id
  from trades t join status_codes s on t.status = s.status_code cross join params p
  where s.is_completed and t.created_at >= p.week_start_utc and t.created_at < p.week_end_utc
), eligible as (            -- F1 + F4: one row per person; the device rule is a visible semi-join
  select distinct c.user_id from completed_trades c
  where exists (select 1 from devices d where d.user_id = c.user_id and d.is_active = 1)
)
select coalesce(h.country, u.country, 'UNKNOWN') as country_as_of_week,   -- F5
       count(*) as active_traders
from eligible e join users u using (user_id)
left join user_country_history h on h.user_id = e.user_id and h.valid_from <= date '2024-01-01'
                                  and (h.valid_to is null or h.valid_to > date '2024-01-01')
group by 1;

-- parity, per country:  legacy.active_traders  - failed_only_users   = refactored.active_traders
--                       legacy.completed_trades - fanout_excess_rows = refactored.completed_trades
```

## AI use, and how I verify it

I would have an AI explain the 400 lines, propose CTEs and enumerate test cases. Its claim that two queries are equivalent is a hypothesis; I check it with the parity test, old against new on past weeks, and a tiny fixture computed by hand. Status codes I confirm with the table's owner, not the AI.

## What I would tell the PM

"You get the country cut this week on the current definition, so nothing you've shown before moves. The corrected version sits beside it, and we switch when we agree the definition."

# Exercise 4 — Your number is "wrong"

*In short: 41% counts trade-device rows, not people who traded; I'd explain the gap, not hide it or match it.*

## What I noticed

Two implementations at different grains. The dashboard counts a trader once per active device: 34 people generate 41 trade-device rows among 100 weekly active users, which reads as 41%. The person-grain table reads 34%. A bridge closes the seven points per country with the fan-out alone, and a test pins it.

## What I would check first

First I rule out rivals: of five definitions on the same week and denominator, only device grain gives 41%. If pressed to present a number I know is wrong, I raise it with my manager.

## What I would say

"Understood; no surprises from me. Keep the 41% in this review, labelled 'device-level (legacy)'. The dashboard counts devices, mine counts people. One slide walks 41 to 34, and every point is a multi-device trader. After the review I send you that slide, and we ask to adopt v2 at the next one, dual-running two cycles. I won't change my table to reproduce 41%: that bakes the double-count into the new source of truth, and someone finds the same seven points in two years with less goodwill than we have now."

## How I would move the org to one definition

```yaml
models:
  - name: fct_weekly_active_traders
    latest_version: 2
    versions:
      - v: 1   # legacy: trades x active devices, deprecation_date 2026-11-13 (two review cycles)
      - v: 2   # distinct weekly active users with a completed trade in the PT week
```

Dashboards on v1 keep working until the date; dbt warns anyone still on it. Put the definition in the semantic layer, with a named owner, so no dashboard owns its own version. For leadership: "The legacy metric counted devices, not people; we move to person-level next review, and here is the bridge."

## What the restatement must check

Recompute two years at person grain: does the trend hold, and would any decision have changed? The double-count may skew segments, not only the level. Power users and some platforms carry more devices, so past segment comparisons (iOS against web, say) may have favored the wrong one.

## Tradeoffs

Restating at once means a surprise and a broken trend line; leaving the legacy metric preserves the defect; dual-running costs two cycles of two labelled numbers. (Talk track and slide: `docs/EXERCISE4_TALK_TRACK.md`.)

# AI disclosure

I used Claude and ChatGPT as engineering assistants: to pressure-test the model, draft and refactor the dbt/SQL/Python, build the synthetic fixtures, review failure modes, generate schema documentation, and draft and edit the written responses. Claude also executed the build, found and fixed a null-handling bug that had dropped every fiat deposit, and wrote its regression tests. I ran the build, reconciliation scripts and CI myself, and the definitions, tradeoffs and stakeholder communication are my own decisions.
