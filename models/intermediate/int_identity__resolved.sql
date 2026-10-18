with x as (
    select * from {{ ref('stg_identity__user_xref') }}
),
resolved_once as (
    select
        x.account_id,
        x.legacy_user_id,
        x.email_hash,
        x.merged_into_account_id,
        coalesce(s.account_id, x.account_id) as canonical_account_id,
        cast(coalesce(x.is_test_account, false) or coalesce(s.is_test_account, false) as boolean) as is_test_account,
        x.xref_updated_at_utc,
        x.merged_into_account_id is not null and s.account_id is null as is_dangling_merge,
        x.merged_into_account_id is not null and s.merged_into_account_id is not null as is_multi_hop_merge
    from x
    left join x s
        on x.merged_into_account_id = s.account_id
),
with_user as (
    select
        *,
        md5(canonical_account_id) as user_sk
    from resolved_once
),
email_collision as (
    select
        email_hash,
        count(distinct user_sk) as n_people
    from with_user
    where email_hash is not null
    group by 1
)
select
    w.user_sk,
    w.canonical_account_id,
    w.account_id,
    w.legacy_user_id,
    w.email_hash,
    w.is_test_account,
    w.is_dangling_merge,
    w.is_multi_hop_merge,
    coalesce(c.n_people > 1, false) as is_email_hash_collision,
    w.xref_updated_at_utc
from with_user w
left join email_collision c using (email_hash)
