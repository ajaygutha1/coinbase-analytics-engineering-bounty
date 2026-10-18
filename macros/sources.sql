{#-
    Switch between the synthetic seed fixtures (default) and the production `source()`
    declarations in models/staging/_sources.yml without touching model SQL.

        dbt build                                   -> reads seeds
        dbt build --vars '{use_seed_sources: false}' -> reads raw_auth.auth_events etc.

    Staging models are the only place this macro is called, so the staging -> intermediate
    -> mart contracts are identical in both modes.
-#}
{% macro funnel_source(source_name, table_name, seed_name) -%}
    {%- if var('use_seed_sources', true) -%}
        {{ ref(seed_name) }}
    {%- else -%}
        {{ source(source_name, table_name) }}
    {%- endif -%}
{%- endmacro %}
