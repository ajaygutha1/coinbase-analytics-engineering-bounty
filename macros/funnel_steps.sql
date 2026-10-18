{% macro funnel_steps() %}
    {{ return([
        {'name':'signed_up','ordinal':1},
        {'name':'email_verified','ordinal':2},
        {'name':'identity_verified','ordinal':3},
        {'name':'first_deposit','ordinal':4},
        {'name':'first_trade','ordinal':5}
    ]) }}
{% endmacro %}
