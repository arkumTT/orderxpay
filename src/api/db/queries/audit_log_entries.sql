-- name: CreateAuditLogEntry :one
INSERT INTO audit_log_entries (actor_id, actor_type, action, target_entity, target_id, before_state, after_state)
VALUES ($1, $2, $3, $4, $5, $6, $7)
RETURNING *;

-- name: ListAuditLogEntriesByTarget :many
SELECT * FROM audit_log_entries
WHERE target_entity = $1 AND target_id = $2
ORDER BY created_at DESC;
