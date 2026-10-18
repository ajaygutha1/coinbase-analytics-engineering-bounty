-- The reversed transfer cannot become Alice's first deposit; the replacement does.
select *
from {{ ref('fct_onboarding_funnel') }}
where account_id = 'ACC-0001'
  and first_deposit_at_utc <> timestamp '2026-09-14 15:46:00'
