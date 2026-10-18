-- Exercise 2 in SQL, as a cross-check of the Python diagnostic (scripts/ex2_diagnose.py).
-- Reads the three generated extracts straight from CSV with DuckDB and reproduces every line of the
-- bridge. Python and SQL must agree; scripts/ex2_sql_crosscheck.py runs this in CI and asserts it.
--
-- Generate the extracts first: python scripts/ex2_make_fixtures.py

{% set day = "date '2026-09-14'" %}
{% set tz = var('reporting_timezone', 'America/Los_Angeles') %}

with system_a as (
    select
        upper(trim(account_id)) as canonical_id,
        cast(created_at_utc as timestamptz) as created_at,
        lower(email) as email
    from read_csv_auto('data/ex2/system_a.csv', header = true, all_varchar = true)
),
system_b as (
    select upper(trim(user_id)) as canonical_id
    from read_csv_auto('data/ex2/system_b.csv', header = true, all_varchar = true)
),
system_c_raw as (
    select account_id, created_at_utc, email
    from read_csv_auto('data/ex2/system_c.csv', header = true, all_varchar = true)
),
-- Step 1: duplicates in System C, three flavours, each with a different fix.
c_dupes as (
    select
        count(*)                                                       as raw_rows,
        count(*) - count(distinct account_id || '|' || created_at_utc || '|' || email) as exact_duplicate_rows,
        count(distinct account_id || '|' || created_at_utc || '|' || email)
            - count(distinct upper(trim(account_id)))                  as case_variant_ids,
        count(distinct upper(trim(account_id)))                        as distinct_canonical_ids
    from system_c_raw
),
-- Step 2: sets, not counts.
a_ids as (select distinct canonical_id from system_a),
b_ids as (select distinct canonical_id from system_b),
b_only as (
    select canonical_id from b_ids
    except
    select canonical_id from a_ids
),
-- Step 3 + 4: time-zone boundary and QA population inside System A.
a_classified as (
    select
        canonical_id,
        email like '%@qa.%' or email like '%.test' as is_qa,
        cast(timezone('{{ tz }}', created_at) as date) < {{ day }} as is_previous_pt_day
    from system_a
),
a_counts as (
    select
        count(distinct canonical_id)                                             as distinct_accounts,
        count(distinct canonical_id) filter (where is_qa)                        as qa_accounts,
        count(distinct canonical_id) filter (where not is_qa and is_previous_pt_day) as previous_pt_day_accounts
    from a_classified
),
-- Step 5: System B is verified-only; the users only B has are the Pacific evening after 24:00Z.
b_counts as (
    select
        (select count(*) from b_ids)  as b_distinct,
        (select count(*) from b_only) as b_only_users
)

-- Step 6: the bridge.
select
    c.raw_rows                                                         as system_c_raw_rows,
    c.exact_duplicate_rows,
    c.case_variant_ids,
    c.distinct_canonical_ids                                           as system_c_distinct_ids,
    a.distinct_accounts                                                as system_a_distinct_ids,
    a.qa_accounts,
    a.previous_pt_day_accounts,
    b.b_only_users                                                     as verified_only_in_b,
    round(b.b_only_users / 0.90)                                       as estimated_pacific_evening_signups,
    a.distinct_accounts - a.qa_accounts - a.previous_pt_day_accounts
        + round(b.b_only_users / 0.90)                                 as recommended_people_pt_day,
    b.b_distinct                                                       as system_b_distinct_ids,
    a.distinct_accounts - a.qa_accounts - a.previous_pt_day_accounts
        + round(b.b_only_users / 0.90) - b.b_distinct                  as signed_up_not_verified
from c_dupes as c
cross join a_counts as a
cross join b_counts as b
