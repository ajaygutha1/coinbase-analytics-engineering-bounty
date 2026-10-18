-- Walk from the trades table (the closest thing to ground truth: one row per completed trade) to the
-- number the legacy dashboard shows as completed_trades. Each step is one named defect, so the walk
-- says how much of the dashboard figure is real trading and how much is artefact:
--
--   completed trades in the week (truth)
--   - trades of users with no active device         legacy inner join drops them (F4)
--   = one row per completed trade, legacy population
--   + extra rows from the devices fan-out           each trade repeated per extra active device (F1)
--   = legacy completed_trades
--
-- The two defects push in opposite directions, which is why the legacy total looked plausible.

with params as (
    select
        cast('{{ var("ex3_week_start_pt", "2024-01-01") }}' as varchar) as week_start,
        cast(cast('{{ var("ex3_week_start_pt", "2024-01-01") }}' as date) + interval '7 day' as varchar) as week_end
),
completed as (
    select t.trade_id, t.user_id
    from {{ ref('ex3_trades') }} t
    join {{ ref('ledger_status_codes') }} s on t.status = s.status_code
    cross join params p
    where s.is_settled
      and t.created_at >= p.week_start and t.created_at < p.week_end
),
devices as (
    select user_id, count(*) as active_devices
    from {{ ref('ex3_devices') }}
    where is_active = 1
    group by user_id
),
steps as (
    select 1 as step_order, 'completed trades in the week (ledger truth)' as step,
           count(*) as trades from completed
    union all
    select 2, 'minus: trades of users with no active device (inner join drops them)',
           -count(*) from completed c left join devices d using (user_id) where d.user_id is null
    union all
    select 4, 'plus: extra rows from the devices fan-out',
           coalesce(sum(d.active_devices - 1), 0) from completed c join devices d using (user_id)
)
select step_order, step, cast(trades as bigint) as trades from steps
union all
select 3, '= one row per completed trade, legacy population', cast(sum(trades) as bigint)
from steps where step_order <= 2
union all
select 5, '= legacy completed_trades (the dashboard)', cast(sum(trades) as bigint)
from steps
order by step_order
