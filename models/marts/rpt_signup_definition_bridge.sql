-- Permanent home for the Exercise 2 conversation: "daily signups" under every definition a
-- stakeholder system might be using, side by side, per Pacific reporting day. When two
-- dashboards disagree, this is a query, not an investigation.
--
-- Grain: one row per signup_date_pt.
--   raw_auth_signup_events_pt      what an event stream reports (System C shape: rows, incl. re-deliveries)
--   distinct_accounts_pt           distinct account ids on the PT day (System A shape)
--   distinct_accounts_utc_day      distinct account ids whose UTC date equals this date (the UTC-day mistake)
--   distinct_people_pt_ex_test     canonical people, merges collapsed, test accounts removed (RECOMMENDED)
--   distinct_people_verified_pt    people who also verified their email (System B shape: verified-only)
--   mart_people_pt_ex_test         what fct_onboarding_funnel reports; must equal distinct_people_pt_ex_test
--   accounts_same_utc_and_pt_day   accounts whose UTC and PT dates agree (the complement is the 17:00-24:00 PT band)

with auth as (
    select * from {{ ref('stg_auth__events') }}
),
identity as (
    select * from {{ ref('int_identity__resolved') }}
),
signups as (
    select
        a.event_id,
        a.account_id,
        a.event_at_utc,
        {{ utc_to_reporting_date('a.event_at_utc') }} as signup_date_pt,
        cast(a.event_at_utc as date) as signup_date_utc,
        i.user_sk,
        coalesce(i.is_test_account, false) as is_test_account
    from auth a
    left join identity i on a.account_id = i.account_id
    where a.event_name = 'account_created'
),
verified_people as (
    select distinct i.user_sk
    from auth a
    join identity i on a.account_id = i.account_id
    where a.event_name = 'email_verified'
),
by_pt_day as (
    select
        s.signup_date_pt,
        count(*) as raw_auth_signup_events_pt,
        count(distinct s.account_id) as distinct_accounts_pt,
        count(distinct s.user_sk) filter (where not s.is_test_account) as distinct_people_pt_ex_test,
        count(distinct s.user_sk) filter (where not s.is_test_account and v.user_sk is not null) as distinct_people_verified_pt,
        count(distinct s.account_id) filter (where s.signup_date_utc = s.signup_date_pt) as accounts_same_utc_and_pt_day
    from signups s
    left join verified_people v on s.user_sk = v.user_sk
    group by 1
),
by_utc_day as (
    select signup_date_utc as signup_date, count(distinct account_id) as distinct_accounts_utc_day
    from signups
    group by 1
),
mart as (
    select signup_date_pt, count(*) as mart_people_pt_ex_test
    from {{ ref('fct_onboarding_funnel') }}
    group by 1
)

select
    coalesce(p.signup_date_pt, m.signup_date_pt) as signup_date_pt,
    coalesce(p.raw_auth_signup_events_pt, 0) as raw_auth_signup_events_pt,
    coalesce(p.distinct_accounts_pt, 0) as distinct_accounts_pt,
    coalesce(u.distinct_accounts_utc_day, 0) as distinct_accounts_utc_day,
    coalesce(p.distinct_people_pt_ex_test, 0) as distinct_people_pt_ex_test,
    coalesce(p.distinct_people_verified_pt, 0) as distinct_people_verified_pt,
    coalesce(m.mart_people_pt_ex_test, 0) as mart_people_pt_ex_test,
    coalesce(p.accounts_same_utc_and_pt_day, 0) as accounts_same_utc_and_pt_day
from by_pt_day p
full outer join mart m on p.signup_date_pt = m.signup_date_pt
left join by_utc_day u on coalesce(p.signup_date_pt, m.signup_date_pt) = u.signup_date
order by 1
