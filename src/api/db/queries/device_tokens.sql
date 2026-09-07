-- name: UpsertDeviceToken :one
-- Re-registering the same token (app relaunch) just bumps updated_at; a
-- token that moved to a different merchant (see migration comment) is
-- repointed rather than rejected.
INSERT INTO device_tokens (merchant_id, fcm_token, platform)
VALUES ($1, $2, $3)
ON CONFLICT (fcm_token) DO UPDATE
  SET merchant_id = EXCLUDED.merchant_id, platform = EXCLUDED.platform
RETURNING *;

-- name: ListDeviceTokensByMerchant :many
SELECT * FROM device_tokens WHERE merchant_id = $1;

-- name: DeleteDeviceToken :exec
DELETE FROM device_tokens WHERE fcm_token = $1;
