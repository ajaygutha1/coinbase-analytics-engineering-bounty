# Architecture

This page explains the pipeline in eight diagrams, from the outside in. Each one answers a single
question, so read them in order or jump to the one you need. GitHub renders the Mermaid blocks.
[`LINEAGE.md`](LINEAGE.md) is the model-level DAG generated from the dbt manifest; this page is the
hand-drawn explanation of why the DAG looks the way it does.

| # | Question | Diagram |
|---|---|---|
| 1 | What is the system, end to end? | [System overview](#1-system-overview) |
| 2 | Where does a bad row get stopped? | [Quality gates by layer](#2-quality-gates-by-layer) |
| 3 | What happens to one messy event? | [Life of an event](#3-life-of-an-event) |
| 4 | How does one person get one key? | [Identity resolution](#4-identity-resolution) |
| 5 | What happens when data arrives late? | [Incremental and late arrivals](#5-incremental-processing-and-late-arrivals) |
| 6 | How do the four exercises connect? | [Exercise map and the fan-out thread](#6-exercise-map-and-the-fan-out-thread) |
| 7 | What proves it works on every push? | [CI pipeline](#7-ci-pipeline) |
| 8 | How would it run in production? | [Production mapping](#8-production-mapping) |

Colour key used throughout: blue = source data, grey = staging and intermediate models, green =
public marts and reports, amber = a gate that can fail the build, rose = a planted problem or a
known risk.

---

## 1. System overview

Four feeds with four different identifier and timestamp conventions go in. One governed person-level
table and one metric layer come out. Everything between them is split so each layer has exactly one
job (rules in the [README layer table](../README.md#layer-rules)).

```mermaid
flowchart LR
  classDef src fill:#dbeafe,stroke:#1d4ed8,color:#0f172a
  classDef mid fill:#e5e7eb,stroke:#4b5563,color:#0f172a
  classDef pub fill:#dcfce7,stroke:#15803d,color:#0f172a
  classDef gate fill:#fef3c7,stroke:#b45309,color:#0f172a
  classDef use fill:#ede9fe,stroke:#6d28d9,color:#0f172a

  subgraph S["Sources: four feeds, four conventions"]
    direction TB
    A1[("auth_events<br/>UUID account_id<br/>ISO-8601 Z")]:::src
    A2[("kyc_events<br/>legacy customer_ref<br/>epoch s or ms")]:::src
    A3[("ledger_transactions<br/>legacy user_id<br/>naive Pacific time")]:::src
    A4[("identity_user_xref<br/>account to legacy id<br/>merges and test flags")]:::src
  end

  G0{{"Gate 0<br/>freshness SLAs"}}:::gate

  subgraph ST["Staging, protected views"]
    direction TB
    B1["stg_auth__events"]:::mid
    B2["stg_kyc__events"]:::mid
    B3["stg_ledger__transactions"]:::mid
    B4["stg_identity__user_xref"]:::mid
  end

  subgraph IN["Intermediate, protected"]
    direction TB
    C1["int_identity__resolved<br/>one key per person"]:::mid
    C2["int_funnel__events<br/>one row per semantic event"]:::mid
    C3["int_funnel__user_steps<br/>person x step"]:::mid
  end

  subgraph M["Marts, public, enforced contracts"]
    direction TB
    D1["fct_onboarding_funnel<br/>one row per person"]:::pub
    D2["fct_onboarding_funnel_daily<br/>cohorts and metrics"]:::pub
    D3["rpt_funnel_data_quality"]:::pub
    D4["rpt_signup_definition_bridge"]:::pub
  end

  subgraph W["Weekly active traders, versioned"]
    direction TB
    E1["v1 legacy, verbatim"]:::pub
    E2["v2 people grain"]:::pub
    E3["rpt_weekly_active_traders_bridge"]:::pub
  end

  U(["Growth Friday review<br/>exposure and semantic layer"]):::use

  A1 --> G0
  A2 --> G0
  A3 --> G0
  A4 --> G0
  G0 --> B1 & B2 & B3 & B4
  B4 --> C1
  B1 & B2 & B3 --> C2
  C1 --> C2
  C2 --> C3
  C3 --> D1
  D1 --> D2 & D3 & D4
  D2 --> U
  E1 --> E3
  E2 --> E3
  E3 --> U
```

**Reading it.** The only door out of the intermediate layer is `fct_onboarding_funnel`, so nobody
can build a dashboard on a half-cleaned table. `protected` access is enforced by dbt groups, which
makes it a build error rather than a convention.

---

## 2. Quality gates by layer

A gate is a check that fails the build (or warns, where the input is known to be imperfect). Each
layer has its own gates, and a problem should be caught at the earliest layer that can see it. The
catalogue of planted problems and the test that catches each is in the
[README](../README.md#data-quality-planted-cases-and-the-tests-that-catch-them).

```mermaid
flowchart TB
  classDef gate fill:#fef3c7,stroke:#b45309,color:#0f172a
  classDef layer fill:#e5e7eb,stroke:#4b5563,color:#0f172a
  classDef pub fill:#dcfce7,stroke:#15803d,color:#0f172a
  classDef warn fill:#ffe4e6,stroke:#be123c,color:#0f172a

  subgraph ROW1["Row 1: from raw feeds to semantic events"]
    direction LR
    L0["Sources"]:::layer --> G0{{"G0 Freshness<br/>auth, KYC: warn 2h, error 12h<br/>ledger: warn 30m, error 2h"}}:::gate
    G0 --> L1["Staging<br/>UTC, canonical ids,<br/>decoded codes, drop<br/>exact re-deliveries only"]:::layer
    L1 --> G1{{"G1 Staging<br/>8 unit tests: epoch s vs ms,<br/>both DST edges, 39-digit<br/>amounts, zero address<br/>unique, not_null, accepted_values"}}:::gate
    G1 --> L2["Identity<br/>follow merge pointers,<br/>flag test accounts"]:::layer
    L2 --> G2{{"G2 Identity<br/>crosswalk cannot fan out<br/>multi-hop and dangling<br/>merges flagged"}}:::gate
    G2 -. "unresolved id 9999:<br/>warn, flag, keep" .-> W1["Warn level<br/>2 intended warnings"]:::warn
    G2 --> L3["Events<br/>union, semantic dedupe,<br/>terminal success rule"]:::layer
    L3 --> G3{{"G3 Events<br/>natural key unique after dedupe<br/>no future events<br/>terminal success never null<br/>settled deposits above<br/>threshold count"}}:::gate
  end

  subgraph ROW2["Row 2: from events to the governed mart"]
    direction LR
    L4["Person x step<br/>first success per step"]:::layer --> G4{{"G4 Grain and order<br/>one row per person and step<br/>funnel monotonic<br/>strict never above observed"}}:::gate
    G4 --> L5["Person mart<br/>pivot, durations, flags"]:::pub
    L5 --> G5{{"G5 Mart<br/>enforced contract<br/>mart reconciles to event layer<br/>no PII columns<br/>test accounts and unresolved<br/>ids excluded"}}:::gate
    G5 --> L6["Daily cohorts<br/>and metrics"]:::pub
    L6 --> G6{{"G6 Metrics<br/>PT and UTC day never drift<br/>over 1 day<br/>weekly bridge closes on every row<br/>legacy output frozen"}}:::gate
    G6 --> OUT(["Consumers"]):::pub
  end

  ROW1 --> ROW2
```

**Why a reconciliation gate and not only uniqueness.** `unique` proves a table has no duplicates; it
cannot prove the table did not silently lose people. G5 compares mart signups to the event layer,
which is the check that would have caught the bug that once dropped every fiat deposit.

---

## 3. Life of an event

This is the decision path one raw row takes. The principle is in
[ADR 0006](adr/0006-flags-not-filters.md): exclusions are flags in the intermediate layer and
filters only in the marts, so every excluded row stays countable.

```mermaid
flowchart TD
  classDef ok fill:#dcfce7,stroke:#15803d,color:#0f172a
  classDef flag fill:#fef3c7,stroke:#b45309,color:#0f172a
  classDef drop fill:#ffe4e6,stroke:#be123c,color:#0f172a
  classDef step fill:#e5e7eb,stroke:#4b5563,color:#0f172a

  R(["Raw row arrives"]):::step --> Q1{"Exact re-delivery<br/>of a row already seen?"}
  Q1 -- yes --> X1["Dropped in staging<br/>the only row dropped anywhere"]:::drop
  Q1 -- no --> N["Normalise<br/>UTC instant, canonical id,<br/>decoded status"]:::step
  N --> Q2{"Identity resolves<br/>to a person?"}
  Q2 -- no --> F1["Keep, set is_identity_unresolved<br/>excluded from mart, counted by warn test"]:::flag
  Q2 -- yes --> Q3{"Test account?"}
  Q3 -- yes --> F2["Keep, set is_test_account<br/>excluded from mart"]:::flag
  Q3 -- no --> Q4{"On-chain deposit?"}
  Q4 -- yes --> K["Key = chain_id : tx_hash : log_index<br/>a re-org restatement updates the event"]:::step
  Q4 -- no --> Q5
  K --> Q5{"Terminal success?"}
  Q5 -- "no: attempt, pending, rejection" --> C["Counted in n_negative_events<br/>never advances a step"]:::flag
  Q5 -- yes --> Q6{"Deposit at least<br/>minimum_deposit_usd<br/>and not a zero-address mint?"}
  Q6 -- no --> C
  Q6 -- yes --> A["Advances the step<br/>first success wins"]:::ok
  A --> Q7{"In order, and ingested<br/>within late_arrival_hours?"}
  Q7 -- yes --> M(["Mart row, no flag"]):::ok
  Q7 -- no --> F3["Mart row with named flag<br/>trade_before_deposit, late_arriving_event,<br/>kyc_revoked_after_approval"]:::flag
```

---

## 4. Identity resolution

Each source names a person differently. The goal is a single `user_sk` that survives merges and is
identical on every rebuild in every warehouse ([ADR 0001](adr/0001-one-row-per-person.md)).

```mermaid
flowchart LR
  classDef src fill:#dbeafe,stroke:#1d4ed8,color:#0f172a
  classDef mid fill:#e5e7eb,stroke:#4b5563,color:#0f172a
  classDef pub fill:#dcfce7,stroke:#15803d,color:#0f172a
  classDef flag fill:#fef3c7,stroke:#b45309,color:#0f172a

  AUTH["auth_events<br/>account_id, mixed case"]:::src --> CAN["Canonicalise<br/>trim, lower case, strip zero padding"]:::mid
  KYC["kyc_events<br/>customer_ref, legacy id"]:::src --> XREF
  LED["ledger_transactions<br/>user_id, legacy id"]:::src --> XREF
  CAN --> HOP["Follow merged_into_account_id<br/>to the surviving account"]:::mid
  XREF[("identity_user_xref<br/>account to legacy id")]:::src --> HOP
  HOP --> SK["user_sk = md5 of the surviving<br/>canonical account id"]:::pub
  XREF -- "legacy id in the crosswalk" --> SK
  XREF -. "legacy id missing<br/>customer_ref 9999" .-> UNR["is_identity_unresolved<br/>LEFT JOIN keeps the row"]:::flag
  HOP -. "multi-hop or dangling merge" .-> FLG["flagged, never guessed"]:::flag
  SK --> KEEP["Merged accounts collapse to one person<br/>and keep the older signup"]:::pub
```

**Design choice.** Every join to identity is a `LEFT JOIN`. An inner join would turn a backlog in
the identity team into an apparent conversion drop in the funnel.

---

## 5. Incremental processing and late arrivals

The event tables are large and the person table is small. The pipeline therefore reads the large
tables once, incrementally, and rebuilds the small table only for people who changed
([ADR 0005](adr/0005-ingestion-time-watermark.md)). The watermark is **ingestion** time, so an
event that happened on Monday and arrives on Thursday is still inside Thursday's window.

```mermaid
sequenceDiagram
  autonumber
  participant Src as Source feeds
  participant Ev as int_funnel__events (merge)
  participant St as int_funnel__user_steps (delete+insert)
  participant Mt as fct_onboarding_funnel (merge)
  participant Dl as Daily, bridge, quality (full refresh)

  Note over Src: Monday event, ingested Thursday
  Src->>Ev: rows with ingested_at above max watermark minus lookback
  Note over Ev: lookback = incremental_lookback_days (3)
  Src->>Ev: rows for ids whose crosswalk changed (merges re-key history)
  Ev->>Ev: merge on event_key, flag is_late_arriving if lag over late_arrival_hours
  Ev->>St: touched people only
  St->>St: delete + insert on user_sk and funnel_step, post-hook removes orphan keys
  St->>Mt: touched people only
  Mt->>Mt: merge on user_sk, contract enforced
  Mt->>Dl: full refresh of cheap aggregates
  Note over Dl: restated cohorts are always correct
```

`scripts/incremental_replay.py` proves this path rather than assuming it: it injects a Monday event
with a Thursday ingestion time, runs the ordinary incremental build, and asserts that exactly one
person's row moved and the cohort count rose by one.

---

## 6. Exercise map and the fan-out thread

The four exercises are one data-contract problem seen at four layers. Exercise 3 and Exercise 4 are
the same defect: a comma join from `trades` to `devices` repeats a trade once per active device.

```mermaid
flowchart TB
  classDef ex fill:#dbeafe,stroke:#1d4ed8,color:#0f172a
  classDef risk fill:#ffe4e6,stroke:#be123c,color:#0f172a
  classDef fix fill:#dcfce7,stroke:#15803d,color:#0f172a
  classDef mid fill:#e5e7eb,stroke:#4b5563,color:#0f172a

  C["One data contract<br/>one person grain, one identity key,<br/>one time-zone rule, one metric definition"]:::mid

  E1["Exercise 1<br/>Design the data model"]:::ex
  E2["Exercise 2<br/>52K / 45K / 57K signups"]:::ex
  E3["Exercise 3<br/>Inherited weekly_active_traders SQL"]:::ex
  E4["Exercise 4<br/>41% vs 34%"]:::ex

  C --> E1 & E2 & E3 & E4

  E1 --> M1["Staging to person mart<br/>with gates"]:::fix
  E2 --> D2["Definition drift:<br/>signup and day mean different things<br/>in each system"]:::risk
  D2 --> P2["ex2_diagnose.py blind diagnostic<br/>Python bridge equals SQL bridge, residual 0<br/>rpt_signup_definition_bridge keeps it permanent"]:::fix

  E3 --> J["users, trades, devices comma join<br/>on user_id"]:::risk
  J --> FO["Fan-out: a trade repeats<br/>once per active device"]:::risk
  FO --> E4
  E4 --> L41["Legacy dashboard 41<br/>counts trades x devices"]:::risk
  E4 --> N34["Person grain 34<br/>distinct people"]:::fix
  L41 --> BR["rpt_weekly_active_traders_bridge<br/>41 rows minus 7 fan-out rows = 34 people"]:::fix
  N34 --> BR

  E3 --> BL["Legacy kept verbatim and frozen<br/>refactor proven by per-country parity"]:::fix
  BR --> PATH["Dual-run: show v1 labelled legacy,<br/>show the bridge, adopt v2, restate history,<br/>deprecate v1 on a dated, owned plan"]:::fix
```

**The thread.** Because Exercise 3 is the defect and Exercise 4 is its symptom, the bridge is
tested to close on every country (`bridge_closes`), and `assert_ex4_only_fanout_reproduces_41`
fails if anything other than the device fan-out is needed to reproduce 41%. The conversation with
the PM is in [`EXERCISE4_TALK_TRACK.md`](EXERCISE4_TALK_TRACK.md).

---

## 7. CI pipeline

Everything CI runs is reachable from `make all`. A cheap `lint` job gates a `build` job so that
style and structure failures never cost a full warehouse build.

```mermaid
flowchart LR
  classDef gate fill:#fef3c7,stroke:#b45309,color:#0f172a
  classDef run fill:#e5e7eb,stroke:#4b5563,color:#0f172a
  classDef proof fill:#dcfce7,stroke:#15803d,color:#0f172a

  subgraph LINT["Job 1: lint"]
    direction TB
    L1{{"ruff"}}:::gate --> L2{{"sqlfluff"}}:::gate --> L3{{"static_validate<br/>YAML, Jinja, refs,<br/>seed widths, guardrails"}}:::gate --> L4{{"pytest<br/>Exercise 2 diagnostic"}}:::gate
  end

  subgraph BUILD["Job 2: build"]
    direction TB
    B1["dbt seed"]:::run --> B2["Full-refresh build<br/>models, contracts, unit and data tests"]:::run
    B2 --> B3["Second build<br/>incremental merge and watermark paths"]:::run
    B3 --> B4["Compile against production<br/>source declarations"]:::run
    B4 --> B5["Compile analyses<br/>legacy, refactor, parity"]:::run
  end

  subgraph PROOF["Proofs, not just checks"]
    direction TB
    P1{{"Exercise 2<br/>blind diagnostic closes the bridge<br/>SQL bridge equals Python bridge"}}:::proof
    P2{{"Exercise 4<br/>41 vs 34 gap equals fan-out rows"}}:::proof
    P3{{"Python oracle<br/>independent expected result<br/>for every planted case"}}:::proof
    P4{{"Late-arrival replay<br/>only the touched person moves"}}:::proof
    P5{{"Docs and lineage<br/>LINEAGE.md must not be stale"}}:::proof
    P1 --> P2 --> P3 --> P4 --> P5
  end

  LINT --> BUILD --> PROOF
```

---

## 8. Production mapping

The project runs on DuckDB so that anyone can build and test it in seconds with no credentials. The
model logic is warehouse-neutral by design: the time-zone, cast and epoch calls are isolated in macros, the
remaining dialect-specific constructs are listed below, and `use_seed_sources: false` already points staging at `source()` declarations. This
section maps each part to the tooling a large analytics team typically runs. The mapping is a plan,
not a claim: only the DuckDB path is executed in CI.

```mermaid
flowchart LR
  classDef here fill:#dcfce7,stroke:#15803d,color:#0f172a
  classDef prod fill:#dbeafe,stroke:#1d4ed8,color:#0f172a
  classDef same fill:#e5e7eb,stroke:#4b5563,color:#0f172a

  subgraph HERE["This repository"]
    direction TB
    H1["CSV seeds"]:::here
    H2["DuckDB"]:::here
    H3["GitHub Actions<br/>make all"]:::here
    H4["exposure and<br/>MetricFlow YAML"]:::here
    H5["dbt groups and access"]:::here
    H6["rpt_funnel_data_quality"]:::here
  end

  subgraph SAME["Unchanged"]
    direction TB
    S1["dbt models, tests,<br/>contracts, unit tests"]:::same
    S2["Macros isolating<br/>dialect-specific calls"]:::same
  end

  subgraph PROD["Production counterpart"]
    direction TB
    P1["Raw tables landed by<br/>ingestion and CDC"]:::prod
    P2["Snowflake, BigQuery<br/>or Databricks SQL"]:::prod
    P3["Airflow or dbt Cloud job<br/>with source freshness first"]:::prod
    P4["Looker or Tableau<br/>reading governed metrics"]:::prod
    P5["Warehouse roles and<br/>grants config"]:::prod
    P6["Alerting on the<br/>quality report"]:::prod
  end

  H1 --> P1
  H2 --> P2
  H3 --> P3
  H4 --> P4
  H5 --> P5
  H6 --> P6
  H1 -.-> S1
  H2 -.-> S2
```

### Component mapping

| Concern | In this repository | Production counterpart | What changes |
|---|---|---|---|
| Raw data | `seeds/` CSVs with planted problems | Raw tables landed by ingestion or CDC | `--vars '{use_seed_sources: false}'`; the `source()` declarations and freshness SLAs already exist |
| Warehouse | DuckDB in process | Snowflake, BigQuery or Databricks SQL | New `profiles.yml` target plus the dialect swaps below |
| Orchestration | GitHub Actions running `make all` | Airflow or dbt Cloud job | Run `dbt source freshness` first, then `dbt build`; a stale feed stops the run |
| Pull request checks | Lint job then full build | Slim CI: `dbt build --select state:modified+ --defer --state <prod artifacts>` | Add a stored production manifest |
| Metrics and BI | `exposure` plus MetricFlow semantic model | Looker or Tableau reading the governed metrics | Point the BI tool at the daily mart; definitions stay in YAML |
| Access control | dbt groups and `access: protected` or `public` | Warehouse roles and dbt `grants:` config | Grant `select` on marts only; staging and intermediate stay private |
| Observability | `rpt_funnel_data_quality`, warn-level tests | Alert on freshness errors and on quality flag rates | Route test failures and report thresholds to the on-call channel |
| Documentation | `dbt docs generate` | Hosted dbt docs or a data catalog | Publish the manifest and catalog artifacts the CI job already uploads |
| Scale | Incremental merge with ingestion-time watermark | Same, plus partition or cluster keys | `ingested_at_utc` on the event table, `signup_date_pt` on the mart |

### Dialect swaps

These are the only places the SQL is not portable. Each is small and local.

| Construct (where) | DuckDB (here) | Snowflake | BigQuery |
|---|---|---|---|
| Time zone conversion (`macros/timezones.sql`) | `timezone('zone', ts)` | `convert_timezone('zone', ts)` | `datetime(ts, 'zone')` and `timestamp(dt, 'zone')` |
| Safe cast (`macros/safe_numeric.sql`) | `try_cast(x as t)` | `try_cast(x as t)` | `safe_cast(x as t)` |
| Epoch to timestamp (`epoch_mixed_to_utc`) | `to_timestamp(seconds)` | `to_timestamp(seconds)` | `timestamp_seconds(seconds)` |
| Conditional aggregate (26 uses of `count(*) filter (where ...)`) | `filter (where ...)` | `count_if(...)` or `sum(case ...)` | `countif(...)` |
| Day spine (`metricflow_time_spine.sql`) | `unnest(generate_series(...))` | `dbt.date_spine` or `generator` | `unnest(generate_date_array(...))` |
| Date difference | `date_diff('unit', a, b)` | `datediff(unit, a, b)` | `date_diff(b, a, unit)` (argument order differs) |
| Delimited string split | `string_split(s, '\|')` | `split(s, '\|')` | `split(s, '\|')` |
| 18-decimal amounts | `decimal(38,18)` | `number(38,18)` | `bignumeric`; `numeric` keeps only 9 decimals |
| `delete+insert` incremental (`int_funnel__user_steps`) | supported | supported | not supported; use `merge` or `insert_overwrite` on a date partition |
| Merge scan cost | full target scan | `incremental_predicates` on the lookback window | partition filter plus `incremental_predicates` |

To port, add the macro per column above (for example a `convert_tz` macro that dispatches on
`target.type`), then run the same `make all` against the new target. The unit tests and the Python
oracle are what make that safe: they fail if the new dialect changes a decoded value.
