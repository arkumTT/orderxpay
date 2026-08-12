-- name: CreateItem :one
INSERT INTO items (merchant_id, name, unit_price_pesewas, qty_unit, image_url, availability_status)
VALUES ($1, $2, $3, $4, $5, $6)
RETURNING *;

-- name: GetItem :one
SELECT * FROM items WHERE id = $1;

-- name: ListItemsByMerchant :many
SELECT * FROM items
WHERE merchant_id = $1 AND archived_at IS NULL
ORDER BY name;

-- name: UpdateItem :one
UPDATE items
SET name = $2,
    unit_price_pesewas = $3,
    qty_unit = $4,
    image_url = $5,
    availability_status = $6
WHERE id = $1
RETURNING *;

-- name: ArchiveItem :exec
UPDATE items SET archived_at = now() WHERE id = $1;
