-- The bridge model rebuilds the legacy numbers from decomposed parts (per-user completed trades x
-- active devices, any-status distinct users). Those parts must add back up to the verbatim legacy
-- query per country, or the decomposition is explaining the wrong number.
select
    b.country,
    b.legacy_completed_trade_rows,
    l.completed_trades       as verbatim_completed_trades,
    b.legacy_distinct_users_any_status,
    l.active_traders         as verbatim_active_traders
from {{ ref('rpt_weekly_active_traders_bridge') }} as b
join {{ ref('rpt_ex3_legacy_characterization') }} as l
    on b.country = l.country
where b.legacy_completed_trade_rows <> l.completed_trades
   or b.legacy_distinct_users_any_status <> l.active_traders
