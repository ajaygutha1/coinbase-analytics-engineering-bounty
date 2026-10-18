-- Exercise 4, before the conversation: is the device fan-out the ONLY thing that could turn 34% into
-- 41%? Each row recomputes "share of weekly active users who traded" under one rival definition on the
-- same week and the same denominator. If a rival also produced 41% the bridge would be explaining the
-- gap with the wrong cause; the test pins that exactly one hypothesis reproduces the legacy number.

with params as (
    select
        cast('{{ var("ex3_week_start_pt", "2024-01-01") }}' as varchar) as week_start,
        cast(cast('{{ var("ex3_week_start_pt", "2024-01-01") }}' as date) + interval '7 day' as varchar) as week_end
),
window_trades as (
    select t.user_id, coalesce(s.is_settled, false) as is_completed
    from {{ ref('ex3_trades') }} t
    left join {{ ref('ledger_status_codes') }} s on t.status = s.status_code
    cross join params p
    where t.created_at >= p.week_start and t.created_at < p.week_end
),
devices as (
    select user_id, count(*) as active_devices
    from {{ ref('ex3_devices') }}
    where is_active = 1
    group by user_id
),
per_user as (
    select
        u.user_id,
        coalesce(d.active_devices, 0)                    as active_devices,
        count(*) filter (where w.is_completed)           as completed_trades,
        count(w.user_id)                                 as any_trades
    from {{ ref('ex3_users') }} u
    left join window_trades w on w.user_id = u.user_id
    left join devices d on d.user_id = u.user_id
    group by u.user_id, d.active_devices
),
denominator as (select count(*) as weekly_active_users from per_user),
hypotheses as (
    select 'H1 device grain: completed-trade rows x active devices (legacy)' as hypothesis,
           sum(completed_trades * active_devices) as numerator, 'device fan-out' as mechanism from per_user
    union all
    select 'H2 attempted trades count: distinct users with ANY trade and an active device',
           count(*) filter (where any_trades > 0 and active_devices > 0), 'status set' from per_user
    union all
    select 'H3 no device rule: distinct users with a completed trade',
           count(*) filter (where completed_trades > 0), 'device eligibility' from per_user
    union all
    select 'H4 completed trade rows, no device join, per active user',
           sum(completed_trades), 'row count instead of people' from per_user
    union all
    select 'H5 person grain: distinct users with a completed trade and an active device (v2)',
           count(*) filter (where completed_trades > 0 and active_devices > 0), 'none (reference)' from per_user
)
select
    h.hypothesis,
    h.mechanism,
    cast(h.numerator as bigint)                                           as numerator,
    cast(d.weekly_active_users as bigint)                                 as weekly_active_users,
    round(cast(h.numerator as double) / d.weekly_active_users, 4)         as share,
    round(cast(h.numerator as double) / d.weekly_active_users, 4) = 0.41 as reproduces_legacy_41
from hypotheses h cross join denominator d
order by h.hypothesis
