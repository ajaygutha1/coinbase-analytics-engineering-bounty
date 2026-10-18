-- Account <-> legacy user id crosswalk.
-- Grain: one row per account_id. Ids are canonicalized here (upper-cased UUIDs, zero-padding
-- stripped from numeric legacy ids) so every downstream join uses the same spelling.

select
    upper(trim(cast(account_id as varchar))) as account_id,
    cast(try_cast(trim(cast(legacy_user_id as varchar)) as bigint) as varchar) as legacy_user_id,
    upper(nullif(trim(cast(merged_into_account_id as varchar)), '')) as merged_into_account_id,
    coalesce(cast(is_test_account as boolean), false) as is_test_account,
    nullif(trim(cast(email_hash as varchar)), '') as email_hash,
    {{ iso_z_to_utc('updated_at_utc') }} as xref_updated_at_utc
from {{ funnel_source('identity', 'user_xref', 'raw_identity_user_xref') }}
