with f as (
    select * from {{ ref('fct_onboarding_funnel') }}
)
select
    signup_date_pt,
    coalesce(signup_country, 'UNKNOWN') as signup_country,
    cast(signup_date_pt as varchar) || '|' || coalesce(signup_country, 'UNKNOWN') as cohort_key,
    count(*)::bigint as users_signed_up,
    sum(cast(reached_email_verified as bigint))::bigint as users_email_verified_observed,
    sum(cast(reached_identity_verified as bigint))::bigint as users_identity_verified_observed,
    sum(cast(reached_first_deposit as bigint))::bigint as users_first_deposit_observed,
    sum(cast(reached_first_trade as bigint))::bigint as users_first_trade_observed,
    sum(cast(furthest_step_strict >= 2 as bigint))::bigint as users_email_verified_strict,
    sum(cast(furthest_step_strict >= 3 as bigint))::bigint as users_identity_verified_strict,
    sum(cast(furthest_step_strict >= 4 as bigint))::bigint as users_first_deposit_strict,
    sum(cast(furthest_step_strict >= 5 as bigint))::bigint as users_first_trade_strict,
    sum(cast(hours_to_first_trade between 0 and 168 as bigint))::bigint as users_first_trade_within_7d,
    -- "today" is the reporting zone's date, not the session's; a UTC or local current_date
    -- would flip maturity a few hours early or late around midnight PT.
    cast(cast(timezone('{{ var("reporting_timezone", "America/Los_Angeles") }}', current_timestamp) as date)
         >= signup_date_pt + interval '7 day' as boolean) as is_cohort_mature_7d,
    max(_loaded_at_utc) as _loaded_at_utc
from f
group by 1, 2, 3
