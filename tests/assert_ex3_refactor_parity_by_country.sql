-- Characterization test for the Exercise 3 refactor, per country. The refactor may differ from
-- the legacy output only by (a) failed-only users in the legacy COUNT(DISTINCT) and (b) the
-- device multiplier in completed_trades. Any row where the bridge does not close is a business
-- rule the refactor changed by accident, and the country cut must not ship.
select *
from {{ ref('rpt_weekly_active_traders_bridge') }}
where not bridge_closes
