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

-- name: SetDeliveryOptionStatus :execrows
-- merchant_id in the WHERE clause — the route path only carries the
-- delivery option's own id, not a merchant id, so ownership has to be
-- enforced here against the caller's token instead.
UPDATE delivery_options SET status = $2 WHERE id = $1 AND merchant_id = $3;
