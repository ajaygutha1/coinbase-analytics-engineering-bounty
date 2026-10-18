with expected as (
    select count(distinct user_sk) as n
    from {{ ref('int_funnel__events') }}
    where funnel_step = 'signed_up'
      and is_terminal_success
      and user_sk is not null
      and not is_test_account
),
actual as (
    select count(*) as n from {{ ref('fct_onboarding_funnel') }}
)
select expected.n as expected_n, actual.n as actual_n
from expected cross join actual
where expected.n <> actual.n
