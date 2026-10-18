-- Boolean flags that feed counting logic must be two-valued. A NULL here means an AND/NOT
-- chain swallowed a null and the row will silently drop out of every aggregate.
select event_key, source_system
from {{ ref('int_funnel__events') }}
where is_terminal_success is null
   or is_negative_outcome is null
   or is_test_account is null
   or is_identity_unresolved is null
