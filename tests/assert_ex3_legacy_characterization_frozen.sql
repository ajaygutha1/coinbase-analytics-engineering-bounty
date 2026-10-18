-- Characterization test: the verbatim legacy query must still produce the output that was frozen
-- before the refactor began. Any difference means the baseline moved, and every parity claim
-- downstream is void until this is understood.
select
    coalesce(live.country, frozen.country) as country,
    live.active_traders   as live_active_traders,
    frozen.active_traders as frozen_active_traders,
    live.completed_trades   as live_completed_trades,
    frozen.completed_trades as frozen_completed_trades
from {{ ref('rpt_ex3_legacy_characterization') }} as live
full outer join {{ ref('ex3_legacy_expected') }} as frozen
    on live.country = frozen.country
where live.country is null
   or frozen.country is null
   or live.active_traders <> frozen.active_traders
   or live.completed_trades <> frozen.completed_trades
