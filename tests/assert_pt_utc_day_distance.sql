select *
from {{ ref('fct_onboarding_funnel') }}
where abs(date_diff('day', signup_date_utc, signup_date_pt)) > 1
