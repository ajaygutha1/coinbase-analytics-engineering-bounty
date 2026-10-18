# ADR 0002 — On-chain deposits are identified by `chain_id + tx_hash + log_index`

**Status:** accepted · **Date:** 2026-09-29

## Context
A ledger row for an on-chain deposit carries a transaction hash. It is tempting to treat the hash
as the identity of the deposit. It is not: one transaction can emit several transfer logs (batch
sends, multiple ERC-20 events), the same hash can exist on two chains, and a re-org can re-emit a
transfer with a different outcome. Separately, the ledger's own `txn_id` is unique per row but two
rows can describe the same on-chain event (a restatement).

## Decision
`stg_ledger__transactions` builds `ledger_business_key = chain_id:tx_hash:log_index` for on-chain
rows and falls back to `txn_id` for fiat and internal rails. `int_funnel__events` uses that key as
its merge key, so a later `settled → reversed` restatement of the same transfer **updates** the
event instead of adding a second deposit. Exact re-deliveries of the same `txn_id` are removed in
staging (latest ingestion wins, because a re-delivered ledger row is a restatement).

## Alternatives rejected
- **Dedupe on `tx_hash`.** Collapses Carol's two legitimate transfer logs into one deposit and
  merges unrelated transfers that share a hash across chains.
- **Dedupe on `txn_id` only.** Keeps Alice's reversed and settled rows as two deposits.

## Consequences
The natural key is not unique in staging (a restatement arrives under a new `txn_id`), which is
deliberate: the audit trail survives and the semantic collapse is one documented step downstream.
If the source never emits a reversal, the model cannot infer chain consensus; production should
ingest a canonical block-status or tombstone feed.
