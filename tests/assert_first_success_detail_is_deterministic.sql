-- At most one chosen first-success detail row per person x step.
select user_sk, funnel_step, count(*) as n
from {{ ref('int_funnel__user_steps') }}
where first_success_at_utc is not null
group by 1,2
having count(*) <> 1
