select *
from {{ ref('fct_onboarding_funnel') }}
where account_id = 'ACC-0005'
  and (furthest_step_observed <> 5 or furthest_step_strict <> 4 or data_quality_flags not like '%trade_before_deposit%')
