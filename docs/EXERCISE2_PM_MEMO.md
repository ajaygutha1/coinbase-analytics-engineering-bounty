# Exercise 2 — what I would send the Growth PM before Friday

*A Slack message or short email, sent the same afternoon. The point is one number, its definition, what is exact vs estimated, and what I need from them. Everything below is produced by `scripts/ex2_diagnose.py`; nothing is hand-typed.*

---

**Subject: Monday signups for the deck — one number, and why the three systems disagree**

Hi —

**Use 50,007** for Monday's new signups, defined as *distinct production people whose first account-created event falls on the Pacific calendar day*. That definition is in the footnote of the slide and, from next week, in the semantic layer so every dashboard reads the same one.

The three systems were each right about something different:

| Line | Count | Confidence |
|---|---:|---|
| System C, raw event rows | 57,000 | exact |
| − exact re-delivered rows (same row twice) | −4,000 | exact |
| − same account id spelled two ways (case) | −1,000 | exact |
| **= System A, distinct accounts on the UTC day** | **52,000** | exact |
| − internal QA accounts (`@qa.…test` domains) | −1,000 | exact |
| − accounts created 00:00–06:59 UTC, i.e. **Sunday** evening Pacific | −4,500 | exact |
| + accounts created Monday evening Pacific that land on Tuesday UTC | +3,507 | **estimate** (see below) |
| **= distinct production people, Pacific Monday** | **50,007** | recommended |
| − signed up but never verified email | −5,004 | derived |
| **= System B, verified-only** | **45,003** | exact |
| Unexplained residual | 0 | |

**What is exact.** Every line except one comes from set differences on canonical ids, so I can hand you the list of accounts behind each number.

**What is an estimate.** The Monday-evening line. System A's extract stops at 24:00 UTC (16:00/17:00 PT), so it never saw Monday-evening signups. System B did see the 3,156 of them that verified email; I grossed that up at the in-day verification rate (90%). If you'd rather not publish an estimate, the exact alternative is 46,500 with the footnote "through 5 pm PT", and I can get the true number by pulling Tuesday's UTC extract from System A (about 30 minutes once I have access).

**What I'd flag.**
1. System C is an event stream, not a people count; re-deliveries mean it will always read high. It should not be used for the headline.
2. System B defines "signup" as *verified*. It is a fine number for a different slide; it is not the same metric.
3. The UTC day boundary moves ~8% of a day's signups. Any historical comparison built on UTC days is shifted by that band.

**What I need from you.** (a) Agree the definition in the footnote; (b) tell me whether Friday's number can carry one labelled estimate or must be the exact "through 5 pm PT" figure; (c) 30 minutes of System A access for the Tuesday extract.

**What happens next.** The bridge above becomes a permanent table (`rpt_signup_definition_bridge`), so the next time two numbers disagree it is a query, not an afternoon.

— Ajay
