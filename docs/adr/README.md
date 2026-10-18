# Architecture decision records

Short records of the decisions that shape this project, in the order they were made. Each one
states the context, the decision, the alternative that was rejected and why, and the consequence
you live with. They exist so the next person can change a decision on purpose instead of by accident.

| # | Decision |
|---|---|
| [0001](0001-one-row-per-person.md) | The deliverable is one row per person, keyed by a surrogate of the canonical account |
| [0002](0002-onchain-natural-key.md) | On-chain deposits are identified by `chain_id + tx_hash + log_index`, never `tx_hash` alone |
| [0003](0003-store-utc-report-pacific.md) | Store UTC, report Pacific, flag DST edge cases instead of guessing |
| [0004](0004-observed-and-strict-funnel.md) | Ship two funnel readings (observed, strict) and name every disagreement |
| [0005](0005-ingestion-time-watermark.md) | Incremental models watermark on ingestion time with a lookback, never on event time |
| [0006](0006-flags-not-filters.md) | Exclusions are flags in the intermediate layer and filters only in marts |
| [0007](0007-versioned-metrics.md) | Metric definitions live in YAML once; a contested metric changes via a model version with a deprecation date |
| [0008](0008-characterization-before-refactor.md) | An inherited pipeline is refactored behind a characterization test, and AI output is verified by parity, not by its own claim |
