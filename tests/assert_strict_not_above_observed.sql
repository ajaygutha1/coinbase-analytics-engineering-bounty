select *
from {{ ref('fct_onboarding_funnel') }}
where furthest_step_strict > furthest_step_observed
