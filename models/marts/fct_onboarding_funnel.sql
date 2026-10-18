{{
  config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='user_sk',
    on_schema_change='fail',
    contract={'enforced': true},
    post_hook="{{ cleanup_funnel_mart_orphans() }}"
  )
}}

-- THE deliverable: one row per person (user_sk), enforced contract, incremental merge.
-- The pivot is deliberately boring: five min(first_success_at_utc) lines over the user x step
-- table. All judgment (identity, dedupe, terminal success) lives upstream where it is unit-testable.
-- Two funnel readings are exposed side by side:
--   furthest_step_observed  = highest step ever completed, any order   (reporting default)
--   furthest_step_strict    = walk the steps in order, stop at the first missing/out-of-order one
-- has_sequence_anomaly and data_quality_flags make the disagreement measurable instead of hidden.

{% set lookback = var('incremental_lookback_days', 3) %}

with steps_all as (
    select * from {{ ref('int_funnel__user_steps') }}
),
{% if is_incremental() %}
mart_watermark as (
    select coalesce(max(_loaded_at_utc), timestamp '1970-01-01') as wm
    from {{ this }}
),
touched_users as (
    select distinct s.user_sk
    from steps_all s
    cross join mart_watermark
    where s._updated_at_utc >= mart_watermark.wm - interval '{{ lookback }} day'
),
steps as (
    select s.*
    from steps_all s
    inner join touched_users t using (user_sk)
),
{% else %}
steps as (select * from steps_all),
{% endif %}
pivoted as (
    select
        user_sk,
        max(canonical_account_id) as account_id,
        min(first_success_at_utc) filter (where funnel_step = 'signed_up') as signed_up_at_utc,
        min(first_success_at_utc) filter (where funnel_step = 'email_verified') as email_verified_at_utc,
        min(first_success_at_utc) filter (where funnel_step = 'identity_verified') as identity_verified_at_utc,
        min(first_success_at_utc) filter (where funnel_step = 'first_deposit') as first_deposit_at_utc,
        min(first_success_at_utc) filter (where funnel_step = 'first_trade') as first_trade_at_utc,
        max(signup_country) filter (where funnel_step = 'signed_up') as signup_country,
        max(n_events) filter (where funnel_step = 'identity_verified') as kyc_events,
        max(n_negative_events) filter (where funnel_step = 'identity_verified') as kyc_negative_events,
        max(n_kyc_revocations) filter (where funnel_step = 'identity_verified') as kyc_revocations,
        max(n_events) filter (where funnel_step = 'first_deposit') as deposit_events,
        max(first_success_usd_notional) filter (where funnel_step = 'first_deposit') as first_deposit_usd,
        max(first_success_deposit_rail) filter (where funnel_step = 'first_deposit') as first_deposit_rail,
        max(cast(has_late_arrival as integer)) = 1 as has_late_arrival,
        max(cast(has_precision_issue as integer)) = 1 as has_precision_issue,
        max(cast(has_dst_ambiguity as integer)) = 1 as has_dst_ambiguity,
        max(cast(has_dst_gap as integer)) = 1 as has_dst_gap,
        max(cast(has_email_hash_collision as integer)) = 1 as has_email_hash_collision
    from steps
    group by 1
),
scored as (
    select
        *,
        signed_up_at_utc is not null as reached_signed_up,
        email_verified_at_utc is not null as reached_email_verified,
        identity_verified_at_utc is not null as reached_identity_verified,
        first_deposit_at_utc is not null as reached_first_deposit,
        first_trade_at_utc is not null as reached_first_trade,
        case
            when first_trade_at_utc is not null then 5
            when first_deposit_at_utc is not null then 4
            when identity_verified_at_utc is not null then 3
            when email_verified_at_utc is not null then 2
            when signed_up_at_utc is not null then 1
            else 0
        end as furthest_step_observed,
        case
            when signed_up_at_utc is null then 0
            when email_verified_at_utc is null or email_verified_at_utc < signed_up_at_utc then 1
            when identity_verified_at_utc is null or identity_verified_at_utc < email_verified_at_utc then 2
            when first_deposit_at_utc is null or first_deposit_at_utc < identity_verified_at_utc then 3
            when first_trade_at_utc is null or first_trade_at_utc < first_deposit_at_utc then 4
            else 5
        end as furthest_step_strict
    from pivoted
)
select
    user_sk,
    cast(account_id as varchar) as account_id,
    cast(signed_up_at_utc as timestamp) as signed_up_at_utc,
    cast(email_verified_at_utc as timestamp) as email_verified_at_utc,
    cast(identity_verified_at_utc as timestamp) as identity_verified_at_utc,
    cast(first_deposit_at_utc as timestamp) as first_deposit_at_utc,
    cast(first_trade_at_utc as timestamp) as first_trade_at_utc,
    cast(reached_signed_up as boolean) as reached_signed_up,
    cast(reached_email_verified as boolean) as reached_email_verified,
    cast(reached_identity_verified as boolean) as reached_identity_verified,
    cast(reached_first_deposit as boolean) as reached_first_deposit,
    cast(reached_first_trade as boolean) as reached_first_trade,
    cast(furthest_step_observed as integer) as furthest_step_observed,
    cast(furthest_step_strict as integer) as furthest_step_strict,
    cast(furthest_step_observed <> furthest_step_strict as boolean) as has_sequence_anomaly,
    cast(concat_ws('|',
        case when email_verified_at_utc < signed_up_at_utc then 'email_before_signup' end,
        case when identity_verified_at_utc < email_verified_at_utc then 'kyc_before_email' end,
        case when first_deposit_at_utc < identity_verified_at_utc then 'deposit_before_kyc' end,
        case when first_trade_at_utc < first_deposit_at_utc then 'trade_before_deposit' end,
        case when coalesce(kyc_revocations, 0) > 0 then 'kyc_revoked_after_approval' end,
        case when has_late_arrival then 'late_arriving_event' end,
        case when has_precision_issue then 'numeric_precision_issue' end,
        case when has_dst_ambiguity then 'dst_ambiguous_local_time' end,
        case when has_dst_gap then 'dst_nonexistent_local_time' end,
        case when has_email_hash_collision then 'email_hash_collision' end
    ) as varchar) as data_quality_flags,
    cast(case when email_verified_at_utc is not null then date_diff('minute', signed_up_at_utc, email_verified_at_utc) end as bigint) as minutes_to_email_verified,
    cast(case when identity_verified_at_utc is not null then date_diff('hour', signed_up_at_utc, identity_verified_at_utc) end as bigint) as hours_to_identity_verified,
    cast(case when first_deposit_at_utc is not null then date_diff('hour', signed_up_at_utc, first_deposit_at_utc) end as bigint) as hours_to_first_deposit,
    cast(case when first_trade_at_utc is not null then date_diff('hour', signed_up_at_utc, first_trade_at_utc) end as bigint) as hours_to_first_trade,
    cast(signed_up_at_utc as date) as signup_date_utc,
    {{ utc_to_reporting_date('signed_up_at_utc') }} as signup_date_pt,
    cast(date_trunc('week', {{ utc_to_reporting_date('signed_up_at_utc') }}) as date) as signup_week_pt,
    cast(signup_country as varchar) as signup_country,
    cast(coalesce(kyc_events, 0) as bigint) as kyc_events,
    cast(coalesce(kyc_negative_events, 0) as bigint) as kyc_negative_events,
    cast(coalesce(deposit_events, 0) as bigint) as deposit_events,
    cast(first_deposit_usd as decimal(38,8)) as first_deposit_usd,
    cast(first_deposit_rail as varchar) as first_deposit_rail,
    cast({{ utc_now() }} as timestamp) as _loaded_at_utc
from scored
where signed_up_at_utc is not null
