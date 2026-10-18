-- The deposit threshold is denominated in USD. A malformed/overflowing USD notional
-- must never silently advance the funnel. Raw crypto amount overflow is flagged and retained
-- because it is not required for this metric.
select event_key, source_event_id
from {{ ref('int_funnel__events') }}
where funnel_step = 'first_deposit'
  and is_terminal_success
  and has_usd_precision_issue
