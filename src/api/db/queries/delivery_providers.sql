-- name: ListDeliveryProviders :many
SELECT * FROM delivery_providers ORDER BY name;

-- name: ListActiveDeliveryProviders :many
-- Merchant-app side of the admin-maintained catalog (Section 4.11/9.4) —
-- only what's actually active, unlike the admin list above which needs to
-- see inactive/retired entries too for management.
SELECT * FROM delivery_providers WHERE status = 'active' ORDER BY name;

-- name: CreateDeliveryProvider :one
INSERT INTO delivery_providers (key, name, deep_link_template, notes)
VALUES ($1, $2, $3, $4)
RETURNING *;

-- name: UpdateDeliveryProvider :one
UPDATE delivery_providers
SET name = $2, deep_link_template = $3, status = $4, notes = $5
WHERE id = $1
RETURNING *;

-- name: DeleteDeliveryProvider :exec
DELETE FROM delivery_providers WHERE id = $1;
