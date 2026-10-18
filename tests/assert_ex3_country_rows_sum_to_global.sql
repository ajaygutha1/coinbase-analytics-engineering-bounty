-- The country cut must add back up to the global number, computed independently of the bridge's own
-- 'ALL' row: per-country v2 traders and users each sum to the v2/v1 model totals, and no user is
-- left without a country label (they land in 'UNKNOWN', visibly).
with by_country as (
    select sum(v2_active_traders) as traders, sum(weekly_active_users) as users
    from {{ ref('rpt_weekly_active_traders_bridge') }}
    where country <> 'ALL'
), v2 as (
    select weekly_active_traders, weekly_active_users
    from {{ ref('fct_weekly_active_traders', version=2) }}
)
select b.traders, v2.weekly_active_traders, b.users, v2.weekly_active_users
from by_country b cross join v2
where b.traders <> v2.weekly_active_traders
   or b.users   <> v2.weekly_active_users
union all
select null, null, null, null
from {{ ref('rpt_weekly_active_traders_bridge') }}
where country is null
