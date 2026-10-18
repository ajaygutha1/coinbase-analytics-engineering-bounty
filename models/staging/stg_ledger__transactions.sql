-- Ledger transactions: deposits, trades, withdrawals, internal moves.
-- Grain: one row per txn_id after exact re-delivery dedupe (latest ingestion wins, because a
-- re-delivered ledger row is a restatement of the same record).
--
-- This is the only staging model with real judgment in it, and each piece is isolated:
--   * status codes are decoded through a seed lookup, never compared as magic integers
--   * naive Pacific wall-clock timestamps become UTC through one macro with a named zone var,
--     and the two DST edge cases are flagged instead of guessed
--   * amounts are kept as the raw string AND as a try_cast fixed-precision decimal, so an
--     overflowing uint256-style value becomes a flag rather than a crash or a rounded number
--   * the zero address is a protocol sentinel, not a counterparty: it becomes a flag and a null
--   * the on-chain natural key is (chain_id, tx_hash, log_index); tx_hash alone is not unique

{% set ledger_tz = var('source_ledger_timezone', 'America/Los_Angeles') %}
{% set zero_address = '0x0000000000000000000000000000000000000000' %}

with normalized as (
    select
        trim(cast(t.txn_id as varchar)) as txn_id,
        cast(try_cast(trim(cast(t.user_id as varchar)) as bigint) as varchar) as legacy_user_id,
        lower(trim(cast(t.txn_type as varchar))) as txn_type,
        cast(t.status_code as integer) as status_code,
        coalesce(s.status_name, 'unknown') as status_name,
        coalesce(s.is_settled, false) as is_settled,

        nullif(trim(cast(t.created_at_local as varchar)), '') as created_at_local_raw,
        {{ local_to_utc('t.created_at_local', ledger_tz) }} as created_at_utc,
        {{ local_to_utc('t.settled_at_local', ledger_tz) }} as settled_at_utc,
        {{ is_dst_ambiguous_local('t.created_at_local', ledger_tz) }} as is_dst_ambiguous_local_time,
        {{ is_dst_nonexistent_local('t.created_at_local', ledger_tz) }} as is_dst_nonexistent_local_time,

        nullif(trim(cast(t.chain_id as varchar)), '') as chain_id,
        lower(nullif(trim(cast(t.tx_hash as varchar)), '')) as tx_hash,
        try_cast(nullif(trim(cast(t.log_index as varchar)), '') as bigint) as log_index,

        -- A null from_address is legitimate (fiat / internal rails). The zero address is a
        -- mint/burn sentinel: expose it as a boolean and null the address so nobody joins on it.
        -- coalesce() matters: a null address must yield false, never null, or every fiat
        -- deposit silently fails the `and not is_from_zero_address` success rule downstream.
        case
            when lower(nullif(trim(cast(t.from_address as varchar)), '')) = '{{ zero_address }}' then null
            else lower(nullif(trim(cast(t.from_address as varchar)), ''))
        end as from_address,
        coalesce(lower(nullif(trim(cast(t.from_address as varchar)), '')) = '{{ zero_address }}', false)
            as is_from_zero_address,

        nullif(trim(cast(t.amount as varchar)), '') as amount_raw,
        nullif(trim(cast(t.usd_notional as varchar)), '') as usd_notional_raw,
        {{ safe_crypto_amount('t.amount') }} as amount,
        {{ safe_usd_amount('t.usd_notional') }} as usd_notional,
        nullif(trim(cast(t.amount as varchar)), '') is not null
            and {{ safe_crypto_amount('t.amount') }} is null as has_amount_precision_issue,
        nullif(trim(cast(t.usd_notional as varchar)), '') is not null
            and {{ safe_usd_amount('t.usd_notional') }} is null as has_usd_precision_issue,

        {{ iso_z_to_utc('t.ingested_at') }} as ingested_at_utc,
        row_number() over (
            partition by trim(cast(t.txn_id as varchar))
            order by {{ iso_z_to_utc('t.ingested_at') }} desc
        ) as _rn
    from {{ funnel_source('ledger', 'ledger_transactions', 'raw_ledger_transactions') }} t
    left join {{ ref('ledger_status_codes') }} s
        on cast(t.status_code as integer) = cast(s.status_code as integer)
)

select
    txn_id,
    legacy_user_id,
    txn_type,
    status_code,
    status_name,
    is_settled,
    created_at_local_raw,
    created_at_utc,
    settled_at_utc,
    is_dst_ambiguous_local_time,
    is_dst_nonexistent_local_time,
    chain_id,
    tx_hash,
    log_index,
    from_address,
    is_from_zero_address,
    amount_raw,
    usd_notional_raw,
    amount,
    usd_notional,
    has_amount_precision_issue,
    has_usd_precision_issue,
    ingested_at_utc,
    case
        when tx_hash is not null and chain_id is not null and log_index is not null
            then chain_id || ':' || tx_hash || ':' || cast(log_index as varchar)
        else txn_id
    end as ledger_business_key,
    case
        when tx_hash is not null then 'onchain'
        when txn_type = 'deposit' then 'fiat'
        else 'internal'
    end as deposit_rail
from normalized
where _rn = 1
