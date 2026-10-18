{% macro cleanup_user_steps_orphans() %}
    delete from {{ this }}
    where user_sk not in (
        select distinct user_sk
        from {{ ref('int_funnel__events') }}
        where user_sk is not null
    )
{% endmacro %}

{% macro cleanup_funnel_mart_orphans() %}
    delete from {{ this }}
    where user_sk not in (
        select distinct user_sk
        from {{ ref('int_funnel__user_steps') }}
        where funnel_step = 'signed_up'
          and first_success_at_utc is not null
    )
{% endmacro %}
