-- Alice's original on-chain deposit is later restated as reversed under the same
-- (chain_id, tx_hash, log_index) business key. The latest restatement must win.
select *
from {{ ref('int_funnel__events') }}
where event_key = 'ledger|1:0xaliceold:0'
  and (source_event_id <> 'l1-reorg' or is_terminal_success or not is_negative_outcome)
