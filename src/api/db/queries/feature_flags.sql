-- name: ListFeatureFlags :many
SELECT * FROM feature_flags ORDER BY name;

-- name: GetFeatureFlagStatusForMerchant :one
-- Enabled if flipped on for everyone, or this merchant is specifically
-- opted in during a staged rollout (Section 7.4). Returns false (not an
-- error) when the key doesn't exist, so callers checking a not-yet-seeded
-- flag key just see "off" rather than needing separate not-found handling.
SELECT COALESCE(
  (SELECT ff.enabled_globally OR EXISTS (
     SELECT 1 FROM feature_flag_merchants ffm
     WHERE ffm.feature_flag_id = ff.id AND ffm.merchant_id = sqlc.arg(merchant_id)
   )
   FROM feature_flags ff
   WHERE ff.key = sqlc.arg(key)),
  false
)::bool AS enabled;

-- name: GetFeatureFlag :one
SELECT * FROM feature_flags WHERE id = $1;

-- name: SetFeatureFlagGlobal :one
UPDATE feature_flags SET enabled_globally = $2 WHERE id = $1
RETURNING *;

-- name: ListFeatureFlagMerchants :many
SELECT ffm.merchant_id, m.business_name
FROM feature_flag_merchants ffm
JOIN merchants m ON m.id = ffm.merchant_id
WHERE ffm.feature_flag_id = $1
ORDER BY m.business_name;

-- name: AddFeatureFlagMerchant :exec
INSERT INTO feature_flag_merchants (feature_flag_id, merchant_id)
VALUES ($1, $2)
ON CONFLICT DO NOTHING;

-- name: RemoveFeatureFlagMerchant :exec
DELETE FROM feature_flag_merchants WHERE feature_flag_id = $1 AND merchant_id = $2;
