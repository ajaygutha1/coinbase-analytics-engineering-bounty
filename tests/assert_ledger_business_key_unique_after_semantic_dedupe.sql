select event_key, count(*) as n
from {{ ref('int_funnel__events') }}
where source_system = 'ledger'
group by 1
having count(*) <> 1
