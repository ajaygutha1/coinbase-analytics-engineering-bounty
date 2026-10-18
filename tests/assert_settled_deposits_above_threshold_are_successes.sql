-- Regression guard for the bug found in build verification: a null from_address (fiat rail)
-- once made `not is_from_zero_address` evaluate to NULL, so no fiat deposit ever counted.
-- Every settled deposit at/above the USD threshold from a non-zero address must be a success.
select event_key, source_event_id, deposit_rail, usd_notional, is_terminal_success
from {{ ref('int_funnel__events') }}
where funnel_step = 'first_deposit'
  and usd_notional >= cast({{ var('minimum_deposit_usd', 1.00) }} as decimal(38,8))
  and not is_from_zero_address
  and not has_usd_precision_issue
  and source_event_id in (
        select l.txn_id from {{ ref('stg_ledger__transactions') }} as l where l.is_settled
      )
  and coalesce(is_terminal_success, false) = false
