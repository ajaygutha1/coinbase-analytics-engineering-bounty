{% macro safe_crypto_amount(expr) -%}
    try_cast(nullif(trim(cast({{ expr }} as varchar)), '') as decimal(38,18))
{%- endmacro %}

{% macro safe_usd_amount(expr) -%}
    try_cast(nullif(trim(cast({{ expr }} as varchar)), '') as decimal(38,8))
{%- endmacro %}
