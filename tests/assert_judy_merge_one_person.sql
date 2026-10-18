select count(*) as n
from {{ ref('fct_onboarding_funnel') }}
where account_id = 'ACC-0011'
having count(*) <> 1
