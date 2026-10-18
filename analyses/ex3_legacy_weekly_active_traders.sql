-- The inherited query, VERBATIM from the challenge (only the table names are ref()'d so it runs
-- on the fixture). Do not "fix" this file: it is the characterization baseline the refactor is
-- measured against. Flags, in the order I would raise them in review:
--
-- F1  FAN-OUT.  users, trades, devices are comma-joined on user_id. devices is one-to-many per
--     user, so every trade row is repeated once per active device. completed_trades is inflated
--     by the device multiplier; active_traders survives only because of COUNT(DISTINCT).
-- F2  WINDOW.   '2024-01-01' .. '2024-01-08' is a hard-coded string compare with no time zone.
--     Nobody can say whether the week is UTC or PT, or whether it moves.
-- F3  MAGIC.    status = 1 OR status = 3 means "completed" to whoever wrote it. A new status 5
--     silently drops out; a decode table would name it.
-- F4  INNER.    Joining devices with is_active = 1 removes traders who have no active device. If
--     that is the business rule it should be a visible semi-join with a count of what it removes.
-- F5  COUNTRY.  u.country is the user's country today. A user who moved is re-attributed
--     retroactively for every historical week.
-- F6  STATUS IN THE WRONG PLACE. The status filter lives only inside the SUM, so active_traders
--     counts anyone with ANY trade row in the window, including failed ones (status 2).
-- F7  NO TESTS, NO OWNER. Nothing would catch any of the above; the author has left.
--
-- On the fixture this returns, per country, active_traders = 36 total (34 completed + 2
-- failed-only) and completed_trades = 41 (34 real trades x device multiplier). The dashboard
-- that shows "41%" divides completed_trades by 100 weekly active users.

SELECT
  u.country,
  COUNT(DISTINCT t.user_id) AS active_traders,
  SUM(CASE WHEN t.status = 1 OR t.status = 3 THEN 1 ELSE 0 END) AS completed_trades
FROM {{ ref('ex3_users') }} u, {{ ref('ex3_trades') }} t, {{ ref('ex3_devices') }} d
WHERE u.user_id = t.user_id
  AND t.user_id = d.user_id
  AND t.created_at >= '2024-01-01'
  AND t.created_at < '2024-01-08'
  AND d.is_active = 1
GROUP BY u.country
