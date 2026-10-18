# Exercise 4 — the conversation, and the one slide

*The PM has pulled me aside during the review: "Can you just make your table match the dashboard? Leadership doesn't want a discrepancy in the deck." Below is what I would actually say, in order, followed by the slide I would offer and the plan I would propose. Numbers come from `rpt_weekly_active_traders_bridge`.*

## What I would say, in the hallway

**1. Acknowledge the constraint first.**
"Understood. Nobody is going to see a surprise in this deck from me. Present the 41% today; it is the number the room knows."

**2. Reframe: two definitions, not a right and a wrong number.**
"They are not competing measurements. The dashboard counts a trader once per active device, so someone trading on a phone and a laptop counts twice. My table counts them once. Both go up and down together; the level is different."

**3. Offer the bridge, not an argument.**
"I have one slide that walks 41% to 34% and every point is explained by multi-device traders. Same week, same people, same denominator. It also shows the trend under both definitions, so leadership sees the story did not change."

**4. Propose the path.**
"For this review, keep 41%, labelled 'definition v1 (device-level)'. After it I add one slide announcing v2 with the bridge. Ask for a decision to adopt v2 from the next review. I dual-run both for two cycles, restate history under v2 so the trend is continuous, and we name an owner. After that, v1 retires on a date we put in writing."

**5. Say what I will not do, and why it protects them.**
"I won't change my table to reproduce 41%, because that would bake the device double-count into the new source of truth. Two years from now someone finds the same seven points and has this conversation with you, with less goodwill than we have today."

**6. Give them the words for leadership.**
"If anyone asks: 'We found the legacy metric counted devices, not people. The trend is unchanged. We are moving to a person-level definition next review and here is the bridge.' That is a data-quality win for Growth, not a mistake."

## Before the hallway: rule out rival explanations

`rpt_ex4_alternative_explanations` recomputes "share of weekly active users who traded" five ways on the same week and denominator. Only the device-grain definition gives 41%; `assert_ex4_only_fanout_reproduces_41` fails if a second one ever does.

| Hypothesis | Share | Reproduces 41%? |
|---|---|---|
| Device grain: completed-trade rows x active devices (legacy) | 41% | yes |
| Attempted trades: any status, active device | 36% | no |
| No device rule: any completed trade | 35% | no |
| Completed trade rows, no device join | 35% | no |
| Person grain with active device (v2) | 34% | no |

If the escalation case arrives (the PM insists on presenting a number I know is wrong), I raise it with my manager rather than correct anyone in the room.

## The one slide

```text
Weekly active traders, week of 2024-01-01 (PT)             share of 100 weekly active users

  Legacy dashboard (definition v1)                                 41%
    counts one row per trader x active device
  − multi-device double counting (7 traders with a 2nd device)      −7 pts
  = Person-level (definition v2)                                   34%

  By country      v1    v2    gap      Also visible in the legacy query, not in the gap:
  US              40%   35%   −5 pts     • its own COUNT(DISTINCT) is 36, not 34: two users whose
  GB              40%   30%  −10 pts       only trade FAILED are counted (status filter sits in the SUM)
  DE              40%   33%   −7 pts     • one trader with no active device is dropped by an inner join
  BR              50%   40%  −10 pts       (rule kept in v2, now counted and visible)

  Trend under both definitions: same shape, different level.   Owner: Growth Analytics
  v1 deprecates 2026-11-13 after two dual-run cycles.            Definition lives in dbt, not in a dashboard.
```

## Where the 41 comes from, trade by trade

`rpt_ex3_trade_walk`: 35 completed trades − 1 trade of a user with no active device (dropped by the inner join) = 34 one-row-per-trade; + 7 fan-out rows = 41. The two defects push in opposite directions, which is why the total never looked wrong.

## How this becomes durable

- `fct_weekly_active_traders` is one model with two versions; dashboards pinned to `v=1` keep working until the deprecation date, and dbt warns anyone still on it.
- `rpt_weekly_active_traders_bridge` is rebuilt on every run, so the bridge is never a one-off spreadsheet.
- `assert_legacy_fanout_gap_exact` and `assert_ex3_refactor_parity_by_country` fail the build if the gap stops being fully explained.
- The metric definition sits in the semantic layer; a dashboard cannot redefine it.

## What I would not say

- "Your number is wrong." It was right for the definition it implemented.
- "Leadership needs to know today." They need a continuous trend and a plan, not a live debate.
- "I'll just change it quietly." That is how the 41% happened in the first place.
