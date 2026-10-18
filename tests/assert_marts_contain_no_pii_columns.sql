-- Marts are widely shared; identity data lives only in staging and the identity layer.
select table_name, column_name
from information_schema.columns
where regexp_matches(table_name, '^(fct|rpt)_')
  and regexp_matches(lower(column_name), '^(email|email_address|phone|first_name|last_name|full_name|address|ssn|dob|date_of_birth)$')
