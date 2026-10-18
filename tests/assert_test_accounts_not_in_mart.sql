select *
from {{ ref('fct_onboarding_funnel') }}
where account_id = 'ACC-QA01'
