-- name: CreateDeliveryOption :one
INSERT INTO delivery_options (merchant_id, type, contact_name, contact_phone, provider_key, deep_link_template, fee_handling_default, flat_fee_pesewas, service_zone)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
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

-- name: UpdateDeliveryOption :execrows
-- Full edit — contact/provider details, flat fee/zone, and fee handling —
-- used by the Delivery Settings screen's edit sheet and by the inline
-- fee-handling selector on already-enabled catalog providers. Same
-- ownership-in-WHERE pattern as SetDeliveryOptionStatus above.
UPDATE delivery_options
SET contact_name = $2,
    contact_phone = $3,
    flat_fee_pesewas = $4,
    service_zone = $5,
    fee_handling_default = $6,
    status = $7
WHERE id = $1 AND merchant_id = $8;
