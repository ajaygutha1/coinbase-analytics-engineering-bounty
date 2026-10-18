-- fct_weekly_active_traders, version 1 (LEGACY, deprecated 2026-11-13).
-- Reproduces the number the two-year-old dashboard shows: "41% of weekly active users made a
-- trade". Its numerator is the inherited query's completed_trades, which is trades x active
-- devices (F1), divided by weekly active users. Kept only so the v1 -> v2 bridge is computed from
-- the same fixture. Nothing here is corrected on purpose.

with legacy as (
    -- verbatim core logic of the inherited query
    select
        count(distinct t.user_id) as active_traders_any_status,
        sum(case when t.status = 1 or t.status = 3 then 1 else 0 end) as completed_trade_rows
    from {{ ref('ex3_users') }} u, {{ ref('ex3_trades') }} t, {{ ref('ex3_devices') }} d
    where u.user_id = t.user_id
      and t.user_id = d.user_id
      and t.created_at >= '{{ var("ex3_week_start_pt", "2024-01-01") }}'
      and t.created_at <  cast(cast('{{ var("ex3_week_start_pt", "2024-01-01") }}' as date) + interval '7 day' as varchar)
      and d.is_active = 1
),
active_users as (
    select count(*) as weekly_active_users
    from {{ ref('ex3_users') }}
    where last_active_at >= '{{ var("ex3_week_start_pt", "2024-01-01") }}'
      and last_active_at <  cast(cast('{{ var("ex3_week_start_pt", "2024-01-01") }}' as date) + interval '7 day' as varchar)
)

select
    cast('{{ var("ex3_week_start_pt", "2024-01-01") }}' as date)   as week_start_pt,
    cast(l.completed_trade_rows as bigint)                          as weekly_active_traders,   -- user x device rows
    cast(l.active_traders_any_status as bigint)                     as legacy_distinct_users_any_status,
    cast(a.weekly_active_users as bigint)                           as weekly_active_users,
    cast(l.completed_trade_rows as double) / nullif(a.weekly_active_users, 0) as trader_share_of_active_users
from legacy l
cross join active_users a
