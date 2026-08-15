-- name: CreateMerchantNote :one
INSERT INTO merchant_notes (merchant_id, author_id, body)
VALUES ($1, $2, $3)
RETURNING *;

-- name: ListMerchantNotes :many
SELECT n.*, u.name AS author_name
FROM merchant_notes n
JOIN users u ON u.id = n.author_id
WHERE n.merchant_id = $1
ORDER BY n.created_at DESC;
