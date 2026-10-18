-- Frank's first raw ledger deposit is a zero-value mint. The valid $25 deposit must be the first success.
select *
from {{ ref('fct_onboarding_funnel') }}
where account_id = 'ACC-0004'
  and (first_deposit_usd <> cast(25.00 as decimal(38,8)) or first_deposit_usd is null)
