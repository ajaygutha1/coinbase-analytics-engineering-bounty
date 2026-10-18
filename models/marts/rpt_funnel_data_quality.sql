-- Observability over the person mart: how many people in each Pacific cohort carry each named
-- data-quality flag, plus the observed-vs-strict disagreement. This is the "how many users have
-- anomalies and why" question as one table, and the first thing to look at when a cohort moves.
-- Grain: one row per signup_date_pt x flag.

with people as (
    select
        signup_date_pt,
        user_sk,
        has_sequence_anomaly,
        data_quality_flags
    from {{ ref('fct_onboarding_funnel') }}
),
cohort_size as (
    select signup_date_pt, count(*) as users_in_cohort
    from people
    group by signup_date_pt
),
exploded as (
    select
        p.signup_date_pt,
        p.user_sk,
        unnest(string_split(p.data_quality_flags, '|')) as flag
    from people as p
    where p.data_quality_flags <> ''

    union all

    select p.signup_date_pt, p.user_sk, 'sequence_anomaly' as flag
    from people as p
    where p.has_sequence_anomaly

    union all

    select p.signup_date_pt, p.user_sk, 'clean' as flag
    from people as p
    where p.data_quality_flags = '' and not p.has_sequence_anomaly
),
counted as (
    select signup_date_pt, flag, count(distinct user_sk) as users_flagged
    from exploded
    group by signup_date_pt, flag
)

select
    c.signup_date_pt,
    c.flag,
    cast(c.users_flagged as bigint) as users_flagged,
    cast(s.users_in_cohort as bigint) as users_in_cohort,
    round(cast(c.users_flagged as double) / nullif(s.users_in_cohort, 0), 4) as share_of_cohort
from counted as c
join cohort_size as s on c.signup_date_pt = s.signup_date_pt
order by c.signup_date_pt, c.flag
