-- Rejected then approved is normal: Bob advances once and keeps one negative KYC event.
select *
from {{ ref('fct_onboarding_funnel') }}
where account_id = 'ACC-0002'
  and (identity_verified_at_utc is null or kyc_negative_events <> 1)
