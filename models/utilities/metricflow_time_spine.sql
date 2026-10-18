{{ config(materialized='table') }}

-- Calendar-day spine required by the dbt semantic layer (MetricFlow). Also used to
-- zero-fill cohort days with no signups so the daily chart does not skip days.
-- Built with DuckDB generate_series so the project has no package dependencies.

with days as (
    select cast(unnest(generate_series(date '2024-01-01', date '2027-12-31', interval 1 day)) as date) as date_day
)

select date_day
from days
