-- The one slide for the Exercise 4 conversation, as a table: per country and in total, how the
-- legacy 41% becomes the person-grain 34%, with every line explained by a named cause.
--
--   legacy_completed_trade_rows   what the dashboard has been dividing by active users (trades x devices)
--   - fanout_excess_rows          the extra rows created by traders with more than one active device
--   = v2_active_traders           distinct people with a completed trade and an active device
--   legacy_distinct_users_any_status  the legacy query's own COUNT(DISTINCT): includes failed-only users
--   failed_only_users             users whose only trades in the week failed (legacy F6)
--   traders_without_active_device users with a completed trade but no active device (dropped by both; F4)
--
-- Attribution uses users.country (today's country) so the rows reconcile to the legacy output;
-- the as-of-week view lives in analyses/ex3_refactored_weekly_active_traders.sql.

with window_trades as (
    select
        t.user_id,
        coalesce(s.is_settled, false) as is_completed
    from {{ ref('ex3_trades') }} t
    left join {{ ref('ledger_status_codes') }} s on t.status = s.status_code
    where t.created_at >= '{{ var("ex3_week_start_pt", "2024-01-01") }}'
      and t.created_at <  cast(cast('{{ var("ex3_week_start_pt", "2024-01-01") }}' as date) + interval '7 day' as varchar)
),
devices as (
    select user_id, count(*) as active_devices
    from {{ ref('ex3_devices') }}
    where is_active = 1
    group by user_id
),
per_user as (
    select
        coalesce(nullif(trim(u.country), ''), 'UNKNOWN') as country,   -- a user with no country is a visible row, never a silent drop
        u.user_id,
        coalesce(d.active_devices, 0)                                   as active_devices,
        count(*) filter (where w.is_completed)                          as completed_trades,
        count(*) filter (where w.is_completed) > 0                      as has_completed_trade,
        count(w.user_id) > 0                                            as has_any_trade   -- left join: count the joined key, not the row
    from {{ ref('ex3_users') }} u
    left join window_trades w on w.user_id = u.user_id
    left join devices d on d.user_id = u.user_id
    group by coalesce(nullif(trim(u.country), ''), 'UNKNOWN'), u.user_id, d.active_devices
),
by_country as (
    select
        country,
        count(*)                                                                             as weekly_active_users,
        sum(completed_trades * active_devices)                                               as legacy_completed_trade_rows,
        count(*) filter (where has_any_trade and active_devices > 0)                         as legacy_distinct_users_any_status,
        count(*) filter (where has_any_trade and not has_completed_trade and active_devices > 0) as failed_only_users,
        count(*) filter (where has_completed_trade and active_devices = 0)                   as traders_without_active_device,
        sum(completed_trades * greatest(active_devices - 1, 0))                              as fanout_excess_rows,
        count(*) filter (where has_completed_trade and active_devices > 0)                   as v2_active_traders
    from per_user
    group by country
),
with_total as (
    select * from by_country
    union all
    select
        'ALL',
        sum(weekly_active_users), sum(legacy_completed_trade_rows), sum(legacy_distinct_users_any_status),
        sum(failed_only_users), sum(traders_without_active_device), sum(fanout_excess_rows), sum(v2_active_traders)
    from by_country
)

select
    cast('{{ var("ex3_week_start_pt", "2024-01-01") }}' as date) as week_start_pt,
    country,
    cast(weekly_active_users as bigint)                as weekly_active_users,
    cast(legacy_completed_trade_rows as bigint)        as legacy_completed_trade_rows,
    cast(fanout_excess_rows as bigint)                 as fanout_excess_rows,
    cast(v2_active_traders as bigint)                  as v2_active_traders,
    cast(legacy_distinct_users_any_status as bigint)   as legacy_distinct_users_any_status,
    cast(failed_only_users as bigint)                  as failed_only_users,
    cast(traders_without_active_device as bigint)      as traders_without_active_device,
    round(cast(legacy_completed_trade_rows as double) / nullif(weekly_active_users, 0), 4) as legacy_share,
    round(cast(v2_active_traders as double) / nullif(weekly_active_users, 0), 4)           as v2_share,
    (legacy_completed_trade_rows - fanout_excess_rows = v2_active_traders)
        and (legacy_distinct_users_any_status - failed_only_users = v2_active_traders)     as bridge_closes
from with_total
order by case when country = 'ALL' then 1 else 0 end, country
