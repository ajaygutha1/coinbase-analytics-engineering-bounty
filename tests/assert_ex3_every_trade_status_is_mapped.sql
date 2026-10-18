-- A status code the lookup does not know (say a new fractional-fill code) would be read as
-- "not completed" and silently shrink the metric. Fail the build the day one appears.
select t.status, count(*) as trades
from {{ ref('ex3_trades') }} t
left join {{ ref('ledger_status_codes') }} s on t.status = s.status_code
where s.status_code is null
group by t.status
