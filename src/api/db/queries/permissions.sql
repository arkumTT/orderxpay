-- name: ListPermissions :many
SELECT * FROM permissions ORDER BY key;

-- name: GetPermissionByKey :one
SELECT * FROM permissions WHERE key = $1;
