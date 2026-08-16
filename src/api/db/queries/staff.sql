-- name: CreateStaff :one
INSERT INTO staff (merchant_id, name, phone, role)
VALUES ($1, $2, $3, $4)
RETURNING *;

-- name: GetStaffByPhone :one
SELECT * FROM staff WHERE phone = $1;

-- name: ListStaffByMerchant :many
SELECT * FROM staff WHERE merchant_id = $1 ORDER BY created_at DESC;

-- name: DeleteStaff :execrows
-- merchant_id in the WHERE clause, not just id — a staff row belongs to
-- exactly one merchant, and the caller must own it (RowsAffected() == 0
-- means either it doesn't exist or belongs to someone else; either way
-- the handler reports 404, not which).
DELETE FROM staff WHERE id = $1 AND merchant_id = $2;
