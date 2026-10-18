-- One on-chain transaction can emit multiple transfer logs. Carol has two log indexes
-- plus an exact txn re-delivery. We should retain two semantic deposits, not three rows.
select *
from {{ ref('fct_onboarding_funnel') }}
where account_id = 'ACC-0003'
  and deposit_events <> 2
