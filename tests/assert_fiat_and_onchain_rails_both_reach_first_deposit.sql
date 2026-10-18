-- Both deposit rails must be able to produce a first deposit. If either rail count is zero on
-- the planted fixture, a rail-specific rule regressed (Alice/Carol are on-chain, Bob/Frank are fiat).
with rails as (
    select first_deposit_rail, count(*) as n
    from {{ ref('fct_onboarding_funnel') }}
    where reached_first_deposit
    group by 1
)
select expected.rail, coalesce(rails.n, 0) as n
from (select 'onchain' as rail union all select 'fiat') as expected
left join rails on rails.first_deposit_rail = expected.rail
where coalesce(rails.n, 0) = 0
