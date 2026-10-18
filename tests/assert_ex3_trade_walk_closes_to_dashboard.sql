-- The ledger-to-dashboard walk must land exactly on the legacy completed_trades the bridge reports,
-- and its truth line must equal the sum of the walk's own steps (no unexplained trades).
with walk as (
    select
        max(trades) filter (where step_order = 3) as legacy_population,
        max(trades) filter (where step_order = 5) as dashboard
    from {{ ref('rpt_ex3_trade_walk') }}
), bridge as (
    select legacy_completed_trade_rows, legacy_completed_trade_rows - fanout_excess_rows as one_row_per_trade
    from {{ ref('rpt_weekly_active_traders_bridge') }} where country = 'ALL'
)
select w.dashboard, b.legacy_completed_trade_rows, w.legacy_population, b.one_row_per_trade
from walk w cross join bridge b
where w.dashboard <> b.legacy_completed_trade_rows
   or w.legacy_population <> b.one_row_per_trade
