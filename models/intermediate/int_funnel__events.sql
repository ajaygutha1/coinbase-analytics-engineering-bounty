{{
  config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='event_key',
    on_schema_change='append_new_columns'
  )
}}

-- Canonical long event table: one row per semantic event across auth, KYC and ledger.
-- Grain: event_key. For on-chain ledger rows the key is chain_id:tx_hash:log_index, so a
-- re-org / restatement of the same transfer UPDATES the row via merge instead of adding a
-- second deposit. Identity joins are LEFT joins: an unresolved id is a flagged row, never a
-- dropped one. Nothing here is aggregated; this is the audit trail the marts are built from.

{% set lookback = var('incremental_lookback_days', 3) %}
{% set min_deposit = var('minimum_deposit_usd', 1.00) %}
{% set late_hours = var('late_arrival_hours', 24) %}

with identity as (
    select * from {{ ref('int_identity__resolved') }}
),
{% if is_incremental() %}
-- Watermark on INGESTION time, never event time: a Monday event that arrives Thursday is
-- still inside Thursday's window. The lookback re-processes late arrivals and restatements.
watermark as (
    select coalesce(max(ingested_at_utc), timestamp '1970-01-01') as processed_wm
    from {{ this }}
),
changed_identity as (
    select identity.account_id, identity.legacy_user_id
    from identity
    cross join watermark
    where identity.xref_updated_at_utc >= watermark.processed_wm - interval '{{ lookback }} day'
),
{% endif %}
auth_base as (
    select a.*
    from {{ ref('stg_auth__events') }} a
    {% if is_incremental() %}
    cross join watermark
    left join changed_identity c on a.account_id = c.account_id
    where a.ingested_at_utc >= watermark.processed_wm - interval '{{ lookback }} day'
       or c.account_id is not null
    {% endif %}
),
kyc_base as (
    select k.*
    from {{ ref('stg_kyc__events') }} k
    {% if is_incremental() %}
    cross join watermark
    left join changed_identity c on k.legacy_user_id = c.legacy_user_id
    where k.ingested_at_utc >= watermark.processed_wm - interval '{{ lookback }} day'
       or c.legacy_user_id is not null
    {% endif %}
),
ledger_base as (
    select l.*
    from {{ ref('stg_ledger__transactions') }} l
    {% if is_incremental() %}
    cross join watermark
    left join changed_identity c on l.legacy_user_id = c.legacy_user_id
    where l.ingested_at_utc >= watermark.processed_wm - interval '{{ lookback }} day'
       or c.legacy_user_id is not null
    {% endif %}
),
auth_events as (
    select
        'auth|' || a.event_id as event_key,
        'auth' as source_system,
        a.event_id as source_event_id,
        i.user_sk,
        i.canonical_account_id,
        a.account_id as source_account_id,
        cast(null as varchar) as legacy_user_id,
        case
            when a.event_name = 'account_created' then 'signed_up'
            when a.event_name = 'email_verified' then 'email_verified'
        end as funnel_step,
        case
            when a.event_name = 'account_created' then 1
            when a.event_name = 'email_verified' then 2
        end as step_ordinal,
        a.event_at_utc,
        a.ingested_at_utc,
        true as is_terminal_success,
        false as is_negative_outcome,
        false as is_kyc_revocation,
        coalesce(i.is_test_account, false) as is_test_account,
        i.user_sk is null as is_identity_unresolved,
        coalesce(i.is_email_hash_collision, false) as is_email_hash_collision,
        a.ip_country as signup_country,
        cast(null as decimal(38,8)) as usd_notional,
        cast(null as varchar) as deposit_rail,
        false as has_amount_precision_issue,
        false as has_usd_precision_issue,
        false as is_from_zero_address,
        false as is_dst_ambiguous_local_time,
        false as is_dst_nonexistent_local_time,
        i.xref_updated_at_utc as identity_updated_at_utc
    from auth_base a
    left join identity i on a.account_id = i.account_id
    where a.event_name in ('account_created', 'email_verified')
),
kyc_events as (
    select
        'kyc|' || k.case_id || '|' || cast(k.attempt_no as varchar) || '|' || k.status_name || '|' || strftime(k.event_at_utc, '%Y%m%d%H%M%S') as event_key,
        'kyc' as source_system,
        k.case_id || ':' || cast(k.attempt_no as varchar) || ':' || k.status_name || ':' || strftime(k.event_at_utc, '%Y%m%d%H%M%S') as source_event_id,
        i.user_sk,
        i.canonical_account_id,
        cast(null as varchar) as source_account_id,
        k.legacy_user_id,
        'identity_verified' as funnel_step,
        3 as step_ordinal,
        k.event_at_utc,
        k.ingested_at_utc,
        k.status_name = 'approved' as is_terminal_success,
        k.status_name in ('rejected', 'revoked') as is_negative_outcome,
        k.status_name = 'revoked' as is_kyc_revocation,
        coalesce(i.is_test_account, false) as is_test_account,
        i.user_sk is null as is_identity_unresolved,
        coalesce(i.is_email_hash_collision, false) as is_email_hash_collision,
        cast(null as varchar) as signup_country,
        cast(null as decimal(38,8)) as usd_notional,
        cast(null as varchar) as deposit_rail,
        false as has_amount_precision_issue,
        false as has_usd_precision_issue,
        false as is_from_zero_address,
        false as is_dst_ambiguous_local_time,
        false as is_dst_nonexistent_local_time,
        i.xref_updated_at_utc as identity_updated_at_utc
    from kyc_base k
    left join identity i on k.legacy_user_id = i.legacy_user_id
),
ledger_events as (
    select
        'ledger|' || l.ledger_business_key as event_key,
        'ledger' as source_system,
        l.txn_id as source_event_id,
        i.user_sk,
        i.canonical_account_id,
        cast(null as varchar) as source_account_id,
        l.legacy_user_id,
        case when l.txn_type = 'deposit' then 'first_deposit' else 'first_trade' end as funnel_step,
        case when l.txn_type = 'deposit' then 4 else 5 end as step_ordinal,
        coalesce(l.settled_at_utc, l.created_at_utc) as event_at_utc,
        l.ingested_at_utc,
        case
            when l.txn_type = 'deposit'
                then l.is_settled
                 and coalesce(l.usd_notional >= cast({{ min_deposit }} as decimal(38,8)), false)
                 and not l.is_from_zero_address
            when l.txn_type = 'trade' then l.is_settled
            else false
        end as is_terminal_success,
        l.status_name in ('failed', 'reversed') as is_negative_outcome,
        false as is_kyc_revocation,
        coalesce(i.is_test_account, false) as is_test_account,
        i.user_sk is null as is_identity_unresolved,
        coalesce(i.is_email_hash_collision, false) as is_email_hash_collision,
        cast(null as varchar) as signup_country,
        l.usd_notional,
        l.deposit_rail,
        l.has_amount_precision_issue,
        l.has_usd_precision_issue,
        l.is_from_zero_address,
        l.is_dst_ambiguous_local_time,
        l.is_dst_nonexistent_local_time,
        i.xref_updated_at_utc as identity_updated_at_utc
    from ledger_base l
    left join identity i on l.legacy_user_id = i.legacy_user_id
    where l.txn_type in ('deposit', 'trade')
),
unioned as (
    select * from auth_events
    union all
    select * from kyc_events
    union all
    select * from ledger_events
),
latest_semantic_event as (
    select
        *,
        row_number() over (
            partition by event_key
            order by ingested_at_utc desc, source_event_id desc
        ) as _semantic_rn
    from unioned
)
select
    event_key,
    source_system,
    source_event_id,
    user_sk,
    canonical_account_id,
    source_account_id,
    legacy_user_id,
    funnel_step,
    step_ordinal,
    event_at_utc,
    ingested_at_utc,
    is_terminal_success,
    is_negative_outcome,
    is_kyc_revocation,
    is_test_account,
    is_identity_unresolved,
    is_email_hash_collision,
    signup_country,
    usd_notional,
    deposit_rail,
    has_amount_precision_issue,
    has_usd_precision_issue,
    is_from_zero_address,
    is_dst_ambiguous_local_time,
    is_dst_nonexistent_local_time,
    ingested_at_utc > event_at_utc + interval '{{ late_hours }} hour' as is_late_arriving,
    identity_updated_at_utc,
    {{ utc_now() }} as _processed_at_utc
from latest_semantic_event
where _semantic_rn = 1
