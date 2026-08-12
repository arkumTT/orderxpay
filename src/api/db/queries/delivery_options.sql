-- name: CreateDeliveryOption :one
INSERT INTO delivery_options (merchant_id, type, contact_name, contact_phone, provider_key, deep_link_template, fee_handling_default)
VALUES ($1, $2, $3, $4, $5, $6, $7)
RETURNING *;

-- name: ListDeliveryOptionsByMerchant :many
SELECT * FROM delivery_options
WHERE merchant_id = $1 AND status = 'active'
ORDER BY created_at;

-- name: GetDeliveryOption :one
SELECT * FROM delivery_options WHERE id = $1;

-- name: SetDeliveryOptionStatus :exec
UPDATE delivery_options SET status = $2 WHERE id = $1;
