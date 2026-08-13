-- name: GrantUserPermission :exec
INSERT INTO user_permissions (user_id, permission_id)
VALUES ($1, $2)
ON CONFLICT DO NOTHING;

-- name: RevokeUserPermission :exec
DELETE FROM user_permissions WHERE user_id = $1 AND permission_id = $2;

-- name: ListUserDirectPermissions :many
SELECT p.* FROM permissions p
JOIN user_permissions up ON up.permission_id = p.id
WHERE up.user_id = $1
ORDER BY p.key;

-- GetUserPermissionKeys is the union of permissions granted via the user's
-- roles and any direct per-user grants — this is what gets embedded in the
-- PASETO token payload at login time.
-- name: GetUserPermissionKeys :many
SELECT DISTINCT p.key FROM permissions p
JOIN role_permissions rp ON rp.permission_id = p.id
JOIN user_roles ur ON ur.role_id = rp.role_id
WHERE ur.user_id = $1
UNION
SELECT DISTINCT p.key FROM permissions p
JOIN user_permissions up ON up.permission_id = p.id
WHERE up.user_id = $1;
