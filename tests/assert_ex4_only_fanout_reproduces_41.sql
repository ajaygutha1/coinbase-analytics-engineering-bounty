-- Uniqueness of the explanation: of the rival definitions, only the device-grain one reproduces 41%.
-- If a second hypothesis ever matched, the bridge would be explaining the gap with the wrong cause.
select count(*) as matching, max(hypothesis) as hypothesis, max(mechanism) as mechanism
from {{ ref('rpt_ex4_alternative_explanations') }}
where reproduces_legacy_41
having count(*) <> 1 or max(mechanism) <> 'device fan-out'
