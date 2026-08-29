-- name: CreateMerchantLocation :one
INSERT INTO merchant_locations (merchant_id, label, address, phone, is_default)
VALUES ($1, $2, $3, $4, $5)
RETURNING *;

-- name: ListMerchantLocationsByMerchant :many
SELECT * FROM merchant_locations
WHERE merchant_id = $1 AND status = 'active'
ORDER BY is_default DESC, created_at;

-- name: GetMerchantLocation :one
SELECT * FROM merchant_locations WHERE id = $1;

-- name: UpdateMerchantLocation :execrows
-- Ownership enforced in the WHERE clause, same pattern as
-- UpdateDeliveryOption — the route path only carries the location's own
-- id, not the merchant id.
UPDATE merchant_locations
SET label = $2,
    address = $3,
    phone = $4,
    status = $5
WHERE id = $1 AND merchant_id = $6;

-- name: ClearDefaultMerchantLocation :exec
-- Step 1 of "set this location as default" — unset whatever the current
-- default is first so the partial unique index (merchant_id) WHERE
-- is_default never sees two defaults at once, even transiently.
UPDATE merchant_locations SET is_default = false WHERE merchant_id = $1 AND is_default;

-- name: SetDefaultMerchantLocation :execrows
UPDATE merchant_locations SET is_default = true WHERE id = $1 AND merchant_id = $2;
