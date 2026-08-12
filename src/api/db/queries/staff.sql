-- name: CreateStaff :one
INSERT INTO staff (merchant_id, name, phone, role)
VALUES ($1, $2, $3, $4)
RETURNING *;

-- name: GetStaffByPhone :one
SELECT * FROM staff WHERE phone = $1;

-- name: ListStaffByMerchant :many
SELECT * FROM staff WHERE merchant_id = $1 ORDER BY created_at DESC;

-- name: DeleteStaff :exec
DELETE FROM staff WHERE id = $1;
