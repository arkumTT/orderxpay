-- name: CreateAdminUser :one
INSERT INTO admin_users (name, email, password_hash, role)
VALUES ($1, $2, $3, $4)
RETURNING *;

-- name: GetAdminUserByEmail :one
SELECT * FROM admin_users WHERE email = $1;

-- name: GetAdminUser :one
SELECT * FROM admin_users WHERE id = $1;

-- name: ListAdminUsers :many
SELECT * FROM admin_users ORDER BY created_at DESC;
