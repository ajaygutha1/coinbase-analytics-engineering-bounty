{{ config(severity='warn') }}
select event_key, source_system, source_event_id, legacy_user_id, source_account_id
from {{ ref('int_funnel__events') }}
where is_identity_unresolved
