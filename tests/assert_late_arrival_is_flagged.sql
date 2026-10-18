select *
from {{ ref('int_funnel__events') }}
where source_event_id in ('l11-dep','l11-trade')
  and not is_late_arriving
