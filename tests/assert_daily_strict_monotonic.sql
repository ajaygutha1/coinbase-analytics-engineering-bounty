select *
from {{ ref('fct_onboarding_funnel_daily') }}
where users_email_verified_strict > users_signed_up
   or users_identity_verified_strict > users_email_verified_strict
   or users_first_deposit_strict > users_identity_verified_strict
   or users_first_trade_strict > users_first_deposit_strict
