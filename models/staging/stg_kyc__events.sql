-- KYC vendor status history.
-- Grain: one row per status change (case_id x attempt_no x status x instant). Retries and
-- regressions (rejected -> approved -> revoked) are real history, not duplicates, so nothing
-- is deduped here. Epoch values arrive in seconds or milliseconds; one macro handles both.

select
    trim(cast(case_id as varchar)) as case_id,
    cast(try_cast(trim(cast(customer_ref as varchar)) as bigint) as varchar) as legacy_user_id,
    lower(trim(cast(status as varchar))) as status_name,
    {{ epoch_mixed_to_utc('updated_at_ms') }} as event_at_utc,
    cast(attempt_no as integer) as attempt_no,
    nullif(trim(cast(vendor as varchar)), '') as vendor,
    {{ iso_z_to_utc('ingested_at') }} as ingested_at_utc
from {{ funnel_source('kyc', 'kyc_events', 'raw_kyc_events') }}
