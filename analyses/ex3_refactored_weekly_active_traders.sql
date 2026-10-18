-- Refactor of the inherited weekly_active_traders query. Same grain, same window (for parity),
-- every flag from the legacy file addressed in a named CTE. Country as-of-week is delivered as a
-- second column so the PM gets the new cut without the metric silently moving.
--
-- How AI was used here, and how it was verified: the model was asked to (1) explain the 400-line
-- original, (2) propose this CTE decomposition, and (3) enumerate test cases. Its claim of
-- equivalence was never trusted; ex3_parity_query.sql is the proof, and it must come back with
-- parity_ok = true for every country before the country cut ships.

{% set week_start_pt = var('ex3_week_start_pt', '2024-01-01') %}
{% set tz = var('reporting_timezone', 'America/Los_Angeles') %}

with params as (                                                            -- F2: the window is named and typed
    select
        cast('{{ week_start_pt }}' as date)                         as week_start_pt,
        cast('{{ week_start_pt }}' as timestamp)                    as legacy_window_start,   -- what the old query meant
        cast('{{ week_start_pt }}' as timestamp) + interval '7 day' as legacy_window_end,
        {{ local_to_utc("'" ~ week_start_pt ~ " 00:00:00'", tz) }}  as pt_window_start_utc,  -- what the business means
        {{ local_to_utc("'" ~ week_start_pt ~ " 00:00:00'", tz) }} + interval '7 day' as pt_window_end_utc
),
statuses as (                                                               -- F3: decode, do not hard-code
    select status_code, status_name, is_settled as is_completed
    from {{ ref('ledger_status_codes') }}
),
completed_trades as (                                                       -- F6: status filter in the WHERE
    select
        t.trade_id,
        t.user_id,
        cast(t.created_at as timestamp) >= p.legacy_window_start
            and cast(t.created_at as timestamp) <  p.legacy_window_end     as in_legacy_window,
        cast(t.created_at as timestamp) >= p.pt_window_start_utc
            and cast(t.created_at as timestamp) <  p.pt_window_end_utc     as in_pt_week
    from {{ ref('ex3_trades') }} t
    cross join params p
    left join statuses s on t.status = s.status_code
    where coalesce(s.is_completed, false)
),
has_active_device as (                                                      -- F4: the rule, visible, one row per user
    select distinct user_id
    from {{ ref('ex3_devices') }}
    where is_active = 1
),
per_trader as (                                                             -- F1: collapse to one row per person BEFORE joining
    select
        c.user_id,
        count(*) filter (where c.in_legacy_window) as completed_trades_legacy_window,
        count(*) filter (where c.in_pt_week)       as completed_trades_pt_week,
        d.user_id is not null                      as is_eligible
    from completed_trades c
    left join has_active_device d using (user_id)
    group by 1, 4
),
country_as_of_week as (                                                     -- F5: attribute to the week, not today
    select h.user_id, h.country
    from {{ ref('ex3_user_country_history') }} h
    cross join params p
    where cast(h.valid_from as date) <= p.week_start_pt
      and (nullif(h.valid_to, '') is null or cast(h.valid_to as date) > p.week_start_pt)
)

select
    u.country                                                   as country_current,      -- parity column
    coalesce(h.country, u.country, 'UNKNOWN')                            as country_as_of_week,   -- the new cut
    count(*) filter (where t.is_eligible and t.completed_trades_legacy_window > 0) as active_traders,
    sum(t.completed_trades_legacy_window) filter (where t.is_eligible)             as completed_trades,
    sum(t.completed_trades_pt_week) filter (where t.is_eligible)                   as completed_trades_if_pt_week,
    count(*) filter (where not t.is_eligible)                                      as traders_dropped_by_active_device_rule
from per_trader t
join {{ ref('ex3_users') }} u using (user_id)
left join country_as_of_week h using (user_id)
group by 1, 2
order by 1, 2
