{#-
    Time-zone helpers. One macro per source encoding so every model column that ends in
    `_at_utc` is a naive TIMESTAMP holding the UTC instant, regardless of how the feed
    delivered it. Never compare a naive `_at_utc` column with `current_timestamp` directly:
    DuckDB would interpret the naive side in the *session* time zone. Use `utc_now()`.
-#}

{# ISO-8601 string with an explicit offset or Z (auth feed) -> naive UTC timestamp #}
{% macro iso_z_to_utc(expr) -%}
    timezone('UTC', cast({{ expr }} as timestamptz))
{%- endmacro %}

{# Epoch value that may be seconds or milliseconds (KYC vendor) -> naive UTC timestamp.
   Anything under 1e11 is treated as seconds (1e11 s is the year 5138; 1e11 ms is 1973). #}
{% macro epoch_mixed_to_utc(expr) -%}
    case
        when {{ expr }} is null then null
        when abs(cast({{ expr }} as double)) < 1e11
            then timezone('UTC', to_timestamp(cast({{ expr }} as double)))
        else timezone('UTC', to_timestamp(cast({{ expr }} as double) / 1000.0))
    end
{%- endmacro %}

{# Naive wall-clock timestamp in a named zone (ledger feed) -> naive UTC timestamp #}
{% macro local_to_utc(expr, timezone_name) -%}
    timezone('UTC', timezone('{{ timezone_name }}', cast({{ expr }} as timestamp)))
{%- endmacro %}

{# Naive UTC timestamp -> calendar date in the reporting zone (the cohort day) #}
{% macro utc_to_reporting_date(expr) -%}
    cast(timezone('{{ var("reporting_timezone", "America/Los_Angeles") }}', timezone('UTC', cast({{ expr }} as timestamp))) as date)
{%- endmacro %}

{# The current instant as a naive UTC timestamp, safe to compare with `_at_utc` columns #}
{% macro utc_now() -%}
    timezone('UTC', current_timestamp)
{%- endmacro %}

{#-
    DST guards for naive local timestamps. Both are zone-agnostic round-trip checks:
    - ambiguous: the wall-clock time occurs twice (fall-back hour). Converting to UTC and
      shifting by +/- 1 hour lands on the *same* wall-clock time again.
    - nonexistent: the wall-clock time never occurred (spring-forward gap). Converting to
      UTC and back does not return the original wall-clock time.
    A naive value cannot tell us which occurrence was meant, so we flag rather than guess.
-#}
{% macro is_dst_ambiguous_local(expr, timezone_name) -%}
    (
        cast({{ expr }} as timestamp) is not null
        and (
            timezone('{{ timezone_name }}', timezone('UTC', {{ local_to_utc(expr, timezone_name) }} - interval '1 hour')) = cast({{ expr }} as timestamp)
            or timezone('{{ timezone_name }}', timezone('UTC', {{ local_to_utc(expr, timezone_name) }} + interval '1 hour')) = cast({{ expr }} as timestamp)
        )
    )
{%- endmacro %}

{% macro is_dst_nonexistent_local(expr, timezone_name) -%}
    (
        cast({{ expr }} as timestamp) is not null
        and timezone('{{ timezone_name }}', timezone('UTC', {{ local_to_utc(expr, timezone_name) }})) <> cast({{ expr }} as timestamp)
    )
{%- endmacro %}
