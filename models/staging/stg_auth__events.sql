-- Auth service events: account creation and email verification.
-- Grain: one row per event_id after exact re-delivery dedupe (earliest ingestion wins).
-- Only normalizes: canonical ids, UTC instants, lower-cased event names. No joins, no filters.

with ranked as (
    select
        cast(event_id as varchar) as event_id,
        upper(trim(cast(account_id as varchar))) as account_id,
        nullif(trim(cast(email_hash as varchar)), '') as email_hash,
        lower(trim(cast(event_name as varchar))) as event_name,
        {{ iso_z_to_utc('event_ts') }} as event_at_utc,
        nullif(trim(cast(device_id as varchar)), '') as device_id,
        upper(nullif(trim(cast(ip_country as varchar)), '')) as ip_country,
        {{ iso_z_to_utc('ingested_at') }} as ingested_at_utc,
        row_number() over (
            partition by cast(event_id as varchar)
            order by {{ iso_z_to_utc('ingested_at') }} asc
        ) as _rn
    from {{ funnel_source('auth', 'auth_events', 'raw_auth_events') }}
)

select
    event_id,
    account_id,
    email_hash,
    event_name,
    event_at_utc,
    device_id,
    ip_country,
    ingested_at_utc
from ranked
where _rn = 1
