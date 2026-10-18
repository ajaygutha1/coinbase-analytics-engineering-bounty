# Lineage

Generated from `target/manifest.json` by `scripts/render_lineage.py`. Seeds are cylinders, models are boxes, the exposure is a pill. Tests are omitted for legibility; `dbt ls --select +exposure:growth_onboarding_review_deck` lists everything the deck depends on.

```mermaid
flowchart LR
  subgraph seeds
    direction TB
    n19[("ex3_devices")]
    n20[("ex3_legacy_expected")]
    n21[("ex3_trades")]
    n22[("ex3_user_country_history")]
    n23[("ex3_users")]
    n24[("ledger_status_codes")]
    n25[("raw_auth_events")]
    n26[("raw_identity_user_xref")]
    n27[("raw_kyc_events")]
    n28[("raw_ledger_transactions")]
  end
  subgraph staging
    direction TB
    n15["stg_auth__events"]
    n16["stg_identity__user_xref"]
    n17["stg_kyc__events"]
    n18["stg_ledger__transactions"]
  end
  subgraph intermediate
    direction TB
    n5["int_funnel__events"]
    n6["int_funnel__user_steps"]
    n7["int_identity__resolved"]
  end
  subgraph marts
    direction TB
    n1["fct_onboarding_funnel"]
    n2["fct_onboarding_funnel_daily"]
    n12["rpt_funnel_data_quality"]
    n13["rpt_signup_definition_bridge"]
  end
  subgraph weekly
    direction TB
    n3["fct_weekly_active_traders v1"]
    n4["fct_weekly_active_traders v2"]
    n9["rpt_ex3_legacy_characterization"]
    n10["rpt_ex3_trade_walk"]
    n11["rpt_ex4_alternative_explanations"]
    n14["rpt_weekly_active_traders_bridge"]
  end
  subgraph utilities
    direction TB
    n8["metricflow_time_spine"]
  end
  subgraph exposures
    direction TB
    n0(["growth_onboarding_review_deck"])
  end
  n1 --> n12
  n1 --> n13
  n1 --> n2
  n15 --> n13
  n15 --> n5
  n16 --> n7
  n17 --> n5
  n18 --> n5
  n19 --> n10
  n19 --> n11
  n19 --> n14
  n19 --> n3
  n19 --> n4
  n19 --> n9
  n2 --> n0
  n21 --> n10
  n21 --> n11
  n21 --> n14
  n21 --> n3
  n21 --> n4
  n21 --> n9
  n23 --> n11
  n23 --> n14
  n23 --> n3
  n23 --> n4
  n23 --> n9
  n24 --> n10
  n24 --> n11
  n24 --> n14
  n24 --> n18
  n24 --> n4
  n25 --> n15
  n26 --> n16
  n27 --> n17
  n28 --> n18
  n5 --> n6
  n6 --> n1
  n7 --> n13
  n7 --> n5
  style n19 fill:#f3f4f6,stroke:#6b7280,color:#111
  style n20 fill:#f3f4f6,stroke:#6b7280,color:#111
  style n21 fill:#f3f4f6,stroke:#6b7280,color:#111
  style n22 fill:#f3f4f6,stroke:#6b7280,color:#111
  style n23 fill:#f3f4f6,stroke:#6b7280,color:#111
  style n24 fill:#f3f4f6,stroke:#6b7280,color:#111
  style n25 fill:#f3f4f6,stroke:#6b7280,color:#111
  style n26 fill:#f3f4f6,stroke:#6b7280,color:#111
  style n27 fill:#f3f4f6,stroke:#6b7280,color:#111
  style n28 fill:#f3f4f6,stroke:#6b7280,color:#111
  style n15 fill:#e0f2fe,stroke:#0284c7,color:#111
  style n16 fill:#e0f2fe,stroke:#0284c7,color:#111
  style n17 fill:#e0f2fe,stroke:#0284c7,color:#111
  style n18 fill:#e0f2fe,stroke:#0284c7,color:#111
  style n5 fill:#fef3c7,stroke:#d97706,color:#111
  style n6 fill:#fef3c7,stroke:#d97706,color:#111
  style n7 fill:#fef3c7,stroke:#d97706,color:#111
  style n1 fill:#dcfce7,stroke:#16a34a,color:#111
  style n2 fill:#dcfce7,stroke:#16a34a,color:#111
  style n12 fill:#dcfce7,stroke:#16a34a,color:#111
  style n13 fill:#dcfce7,stroke:#16a34a,color:#111
  style n3 fill:#ede9fe,stroke:#7c3aed,color:#111
  style n4 fill:#ede9fe,stroke:#7c3aed,color:#111
  style n9 fill:#ede9fe,stroke:#7c3aed,color:#111
  style n10 fill:#ede9fe,stroke:#7c3aed,color:#111
  style n11 fill:#ede9fe,stroke:#7c3aed,color:#111
  style n14 fill:#ede9fe,stroke:#7c3aed,color:#111
  style n8 fill:#f3f4f6,stroke:#6b7280,color:#111
  style n0 fill:#fee2e2,stroke:#dc2626,color:#111
```
