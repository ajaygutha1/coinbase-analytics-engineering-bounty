select *
from {{ ref('fct_onboarding_funnel') }}
where first_deposit_usd is not null
  and first_deposit_usd < cast({{ var('minimum_deposit_usd', 1.00) }} as decimal(38,8))
