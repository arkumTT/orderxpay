-- name: ListRoles :many
SELECT * FROM roles ORDER BY name;

-- name: GetRoleByName :one
SELECT * FROM roles WHERE name = $1;

-- name: ListPermissionsByRole :many
SELECT p.* FROM permissions p
JOIN role_permissions rp ON rp.permission_id = p.id
WHERE rp.role_id = $1
ORDER BY p.key;
