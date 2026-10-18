-- fct_weekly_active_traders, version 2 (CURRENT).
-- One person counts once. A weekly active trader is a weekly active user with at least one
-- COMPLETED trade (status decoded, not hard-coded) inside the Pacific week, who has at least one
-- active device (the legacy rule, kept, but as an EXISTS semi-join that cannot multiply rows).

{% set week_start_pt = var('ex3_week_start_pt', '2024-01-01') %}
{% set tz = var('reporting_timezone', 'America/Los_Angeles') %}

with params as (
    select
        cast('{{ week_start_pt }}' as date) as week_start_pt,
        {{ local_to_utc("'" ~ week_start_pt ~ " 00:00:00'", tz) }} as week_start_utc,
        {{ local_to_utc("'" ~ week_start_pt ~ " 00:00:00'", tz) }} + interval '7 day' as week_end_utc
),
completed_traders as (
    select distinct t.user_id
    from {{ ref('ex3_trades') }} t
    cross join params p
    left join {{ ref('ledger_status_codes') }} s on t.status = s.status_code
    where coalesce(s.is_settled, false)
      and cast(t.created_at as timestamp) >= p.week_start_utc
      and cast(t.created_at as timestamp) <  p.week_end_utc
),
eligible_traders as (
    select c.user_id
    from completed_traders c
    where exists (
        select 1
        from {{ ref('ex3_devices') }} d
        where d.user_id = c.user_id
          and d.is_active = 1
    )
),
active_users as (
    select count(*) as weekly_active_users
    from {{ ref('ex3_users') }} u
    cross join params p
    where cast(u.last_active_at as timestamp) >= p.week_start_utc
      and cast(u.last_active_at as timestamp) <  p.week_end_utc
)

select
    p.week_start_pt,
    cast(count(e.user_id) as bigint)                                 as weekly_active_traders,   -- distinct people
    cast(max(a.weekly_active_users) as bigint)                       as weekly_active_users,
    cast(count(e.user_id) as double) / nullif(max(a.weekly_active_users), 0) as trader_share_of_active_users
from params p
cross join active_users a
left join eligible_traders e on true
group by 1
