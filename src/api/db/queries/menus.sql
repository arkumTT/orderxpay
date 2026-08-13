-- name: CreateMenu :one
INSERT INTO menus (parent_id, permission_id, label, path, icon, sort_order)
VALUES ($1, $2, $3, $4, $5, $6)
RETURNING *;

-- name: GetMenu :one
SELECT * FROM menus WHERE id = $1;

-- name: UpdateMenu :one
UPDATE menus
SET parent_id = $2, permission_id = $3, label = $4, path = $5, icon = $6, sort_order = $7
WHERE id = $1
RETURNING *;

-- name: DeleteMenu :exec
DELETE FROM menus WHERE id = $1;

-- name: ListMenus :many
SELECT * FROM menus ORDER BY sort_order, label;

-- ListMenusForUser returns every menu with no permission requirement, every
-- menu whose permission is among the caller's effective permissions (via
-- role or direct grant), AND every ancestor of such a menu — otherwise a
-- child could pass its own permission check while its parent doesn't,
-- leaving it with no reachable parent in the assembled tree. This is what
-- the Back Office sidebar calls.
-- name: ListMenusForUser :many
WITH RECURSIVE granted AS (
  SELECT m.* FROM menus m
  WHERE m.permission_id IS NULL
     OR m.permission_id IN (
       SELECT p.id FROM permissions p
       JOIN role_permissions rp ON rp.permission_id = p.id
       JOIN user_roles ur ON ur.role_id = rp.role_id
       WHERE ur.user_id = $1
       UNION
       SELECT p.id FROM permissions p
       JOIN user_permissions up ON up.permission_id = p.id
       WHERE up.user_id = $1
     )
), visible AS (
  SELECT * FROM granted
  UNION
  SELECT m.* FROM menus m
  JOIN visible v ON m.id = v.parent_id
)
SELECT * FROM visible ORDER BY sort_order, label;
