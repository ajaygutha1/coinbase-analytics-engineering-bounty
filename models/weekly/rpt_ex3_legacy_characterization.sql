-- The inherited query's core logic, VERBATIM, grouped by country, materialized so it can be
-- tested. This is the characterization baseline for the Exercise 3 refactor:
--   * assert_ex3_legacy_characterization_frozen compares it to seeds/ex3_legacy_expected.csv, the
--     output frozen before any refactoring started. If this test fails, the LEGACY behaviour moved
--     (data or environment), and no parity claim about the refactor means anything.
--   * assert_ex3_refactor_parity_by_country compares the refactor against it per country.
-- Do not "fix" anything here; the flags are documented in analyses/ex3_legacy_weekly_active_traders.sql.

select
    u.country,
    count(distinct t.user_id) as active_traders,
    sum(case when t.status = 1 or t.status = 3 then 1 else 0 end) as completed_trades
from {{ ref('ex3_users') }} as u, {{ ref('ex3_trades') }} as t, {{ ref('ex3_devices') }} as d
where u.user_id = t.user_id
  and t.user_id = d.user_id
  and t.created_at >= '{{ var("ex3_week_start_pt", "2024-01-01") }}'
  and t.created_at < cast(cast('{{ var("ex3_week_start_pt", "2024-01-01") }}' as date) + interval '7 day' as varchar)
  and d.is_active = 1
group by u.country
