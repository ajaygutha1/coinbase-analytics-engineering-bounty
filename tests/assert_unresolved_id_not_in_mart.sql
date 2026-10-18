-- Unresolved identities stay visible in the canonical event layer but cannot enter the person-grain mart.
select e.*
from {{ ref('int_funnel__events') }} e
join {{ ref('fct_onboarding_funnel') }} f using (user_sk)
where e.is_identity_unresolved
