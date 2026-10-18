-- One row per canonical person x funnel step is a structural guard against fan-out.
select user_sk, funnel_step, count(*) as n
from {{ ref('int_funnel__user_steps') }}
group by 1, 2
having count(*) <> 1
