-- Approval advances the historical funnel; later revocation remains an audit flag.
select *
from {{ ref('fct_onboarding_funnel') }}
where account_id = 'ACC-0006'
  and (identity_verified_at_utc is null or data_quality_flags not like '%kyc_revoked_after_approval%')
