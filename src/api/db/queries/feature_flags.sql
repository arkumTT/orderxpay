-- name: ListFeatureFlags :many
SELECT * FROM feature_flags ORDER BY name;

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
