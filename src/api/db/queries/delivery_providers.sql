-- name: ListDeliveryProviders :many
SELECT * FROM delivery_providers ORDER BY name;

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
