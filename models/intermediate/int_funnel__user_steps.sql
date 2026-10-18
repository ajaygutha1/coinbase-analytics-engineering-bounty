{{
  config(
    materialized='incremental',
    incremental_strategy='delete+insert',
    unique_key=['user_sk', 'funnel_step'],
    post_hook="{{ cleanup_user_steps_orphans() }}"
  )
}}

-- One row per canonical person x funnel step.
-- The step's timestamp is the FIRST terminal success (min over successes); attempts, pending
-- states, rejections and revocations are counted alongside it, never used to advance the step.
-- First-success detail (rail, USD, country) is chosen deterministically by (event_at_utc, event_key)
-- so a timestamp tie cannot flip the answer between runs.

{% set lookback = var('incremental_lookback_days', 3) %}

with events_all as (
    select *
    from {{ ref('int_funnel__events') }}
    where user_sk is not null
      and not is_test_account
),
{% if is_incremental() %}
step_watermark as (
    select coalesce(max(_updated_at_utc), timestamp '1970-01-01') as wm
    from {{ this }}
),
touched_users as (
    select distinct e.user_sk
    from events_all e
    cross join step_watermark
    where greatest(e.ingested_at_utc, coalesce(e.identity_updated_at_utc, e.ingested_at_utc))
          >= step_watermark.wm - interval '{{ lookback }} day'
),
events as (
    select e.*
    from events_all e
    inner join touched_users t using (user_sk)
),
{% else %}
events as (
    select * from events_all
),
{% endif %}
aggregated as (
    select
        user_sk,
        funnel_step,
        max(step_ordinal) as step_ordinal,
        min(event_at_utc) filter (where is_terminal_success) as first_success_at_utc,
        count(*) as n_events,
        sum(cast(is_negative_outcome as bigint)) as n_negative_events,
        sum(cast(is_kyc_revocation as bigint)) as n_kyc_revocations,
        max(cast(is_late_arriving as integer)) = 1 as has_late_arrival,
        max(cast(has_amount_precision_issue or has_usd_precision_issue as integer)) = 1 as has_precision_issue,
        max(cast(is_dst_ambiguous_local_time as integer)) = 1 as has_dst_ambiguity,
        max(cast(is_dst_nonexistent_local_time as integer)) = 1 as has_dst_gap,
        max(cast(is_email_hash_collision as integer)) = 1 as has_email_hash_collision,
        max(ingested_at_utc) as _updated_at_utc
    from events
    group by 1, 2
),
success_ranked as (
    select
        e.*,
        row_number() over (
            partition by e.user_sk, e.funnel_step
            order by e.event_at_utc, e.event_key
        ) as success_rn
    from events e
    where e.is_terminal_success
),
first_success_detail as (
    select
        user_sk,
        funnel_step,
        canonical_account_id,
        signup_country,
        usd_notional as first_success_usd_notional,
        deposit_rail as first_success_deposit_rail
    from success_ranked
    where success_rn = 1
)
select
    a.user_sk,
    a.funnel_step,
    a.step_ordinal,
    a.first_success_at_utc,
    a.n_events,
    a.n_negative_events,
    a.n_kyc_revocations,
    a.has_late_arrival,
    a.has_precision_issue,
    a.has_dst_ambiguity,
    a.has_dst_gap,
    a.has_email_hash_collision,
    d.canonical_account_id,
    d.signup_country,
    d.first_success_usd_notional,
    d.first_success_deposit_rail,
    a._updated_at_utc
from aggregated a
left join first_success_detail d
    on a.user_sk = d.user_sk and a.funnel_step = d.funnel_step
