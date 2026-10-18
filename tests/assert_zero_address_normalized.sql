select *
from {{ ref('stg_ledger__transactions') }}
where txn_id = 'l4-zero'
  and (not is_from_zero_address or from_address is not null)
