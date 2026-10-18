select event_key, count(*) as n
from {{ ref('int_funnel__events') }}
group by 1
having count(*) > 1
