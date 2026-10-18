-- An event in the future almost always means an epoch-seconds value was read as
-- milliseconds (or vice versa). Compare against a UTC instant, never raw current_timestamp,
-- because event_at_utc is a naive UTC column and DuckDB would otherwise interpret it in the
-- session time zone.
select event_key, source_system, event_at_utc
from {{ ref('int_funnel__events') }}
where event_at_utc > {{ utc_now() }} + interval '5 minute'
