-- Characterization / parity query. Run BEFORE shipping the country cut.
-- The refactor is allowed to differ from the legacy output in exactly two, fully explained ways:
--   * active_traders differs by the users whose only trades FAILED (legacy F6 counted them);
--   * completed_trades differs by the device multiplier (legacy F1 fan-out).
-- Anything else means the refactor changed a business rule, and the country cut does not ship.
-- The same logic is materialized as rpt_weekly_active_traders_bridge and pinned by a test.

with legacy as (
    select
        u.country,
        count(distinct t.user_id) as active_traders,
        sum(case when t.status = 1 or t.status = 3 then 1 else 0 end) as completed_trades
    from {{ ref('ex3_users') }} u, {{ ref('ex3_trades') }} t, {{ ref('ex3_devices') }} d
    where u.user_id = t.user_id
      and t.user_id = d.user_id
      and t.created_at >= '2024-01-01'
      and t.created_at <  '2024-01-08'
      and d.is_active = 1
    group by u.country
),
trades_in_window as (
    select t.*, coalesce(s.is_settled, false) as is_completed
    from {{ ref('ex3_trades') }} t
    left join {{ ref('ledger_status_codes') }} s on t.status = s.status_code
    where t.created_at >= '2024-01-01' and t.created_at < '2024-01-08'
),
with_device as (
    select distinct user_id from {{ ref('ex3_devices') }} where is_active = 1
),
per_user as (
    select
        u.country,
        u.user_id,
        max(case when t.is_completed then 1 else 0 end) = 1 as has_completed_trade,
        count(*) filter (where t.is_completed)              as completed_trades,
        (select count(*) from {{ ref('ex3_devices') }} d where d.user_id = u.user_id and d.is_active = 1) as active_devices
    from {{ ref('ex3_users') }} u
    join trades_in_window t on t.user_id = u.user_id
    join with_device w on w.user_id = u.user_id
    group by u.country, u.user_id
),
refactored as (
    select
        country,
        count(*) filter (where has_completed_trade)                          as active_traders,
        sum(completed_trades)                                                as completed_trades,
        count(*) filter (where not has_completed_trade)                      as failed_only_users,
        sum(completed_trades * (active_devices - 1))                         as fanout_excess_rows
    from per_user
    group by country
)
select
    l.country,
    l.active_traders            as legacy_active_traders,
    r.active_traders            as refactored_active_traders,
    r.failed_only_users,
    l.completed_trades          as legacy_completed_trades,
    r.completed_trades          as refactored_completed_trades,
    r.fanout_excess_rows,
    round(cast(l.completed_trades as double) / nullif(r.completed_trades, 0), 3) as device_multiplier,
    (l.active_traders - r.failed_only_users = r.active_traders)
        and (l.completed_trades - r.fanout_excess_rows = r.completed_trades)   as parity_ok
from legacy l
full outer join refactored r using (country)
order by l.country
