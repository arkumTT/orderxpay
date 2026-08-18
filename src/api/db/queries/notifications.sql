-- name: CreateNotification :one
INSERT INTO notifications (merchant_id, type, title, body, target_entity, target_id)
VALUES ($1, $2, $3, $4, $5, $6)
RETURNING *;

-- name: ListNotificationsByMerchant :many
SELECT * FROM notifications
WHERE merchant_id = $1
ORDER BY created_at DESC
LIMIT $2 OFFSET $3;

-- name: CountUnreadNotifications :one
SELECT COUNT(*) FROM notifications WHERE merchant_id = $1 AND read_at IS NULL;

-- name: MarkNotificationRead :execrows
UPDATE notifications SET read_at = now()
WHERE id = $1 AND merchant_id = $2 AND read_at IS NULL;

-- name: MarkAllNotificationsRead :exec
UPDATE notifications SET read_at = now()
WHERE merchant_id = $1 AND read_at IS NULL;
