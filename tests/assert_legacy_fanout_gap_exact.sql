-- The planted fixture must reproduce the challenge exactly: 41% under the legacy definition,
-- 34% under the person-grain definition, same denominator of 100 weekly active users, and the
-- 7-point gap fully explained by the devices fan-out in the bridge model.
with v1 as (
    select * from {{ ref('fct_weekly_active_traders', version=1) }}
), v2 as (
    select * from {{ ref('fct_weekly_active_traders', version=2) }}
), bridge as (
    select * from {{ ref('rpt_weekly_active_traders_bridge') }} where country = 'ALL'
)
select
    v1.weekly_active_traders as legacy,
    v2.weekly_active_traders as corrected,
    v1.weekly_active_users   as denominator,
    bridge.fanout_excess_rows
from v1 cross join v2 cross join bridge
where v1.weekly_active_traders <> 41
   or v2.weekly_active_traders <> 34
   or v1.weekly_active_users <> 100
   or v2.weekly_active_users <> 100
   or v1.legacy_distinct_users_any_status <> 36
   or abs(v1.trader_share_of_active_users - 0.41) > 0.000001
   or abs(v2.trader_share_of_active_users - 0.34) > 0.000001
   or bridge.fanout_excess_rows <> 7
   or bridge.legacy_completed_trade_rows - bridge.fanout_excess_rows <> v2.weekly_active_traders
