-- name: CreateAuditLogEntry :one
INSERT INTO audit_log_entries (actor_id, actor_type, action, target_entity, target_id, before_state, after_state)
VALUES ($1, $2, $3, $4, $5, $6, $7)
RETURNING *;

-- name: ListAuditLogEntriesByTarget :many
SELECT * FROM audit_log_entries
WHERE target_entity = $1 AND target_id = $2
ORDER BY created_at DESC;

-- name: ListAuditLogEntriesAdmin :many
-- Section 7.9 compliance log view. Joins to users for a display name/email
-- when actor_type = 'user' — 'system'-actor entries (webhook/reconciliation
-- writes) have no row to join and are left as actor_name = NULL.
SELECT ale.id, ale.actor_id, ale.actor_type, ale.action, ale.target_entity, ale.target_id,
       ale.before_state, ale.after_state, ale.created_at,
       u.name AS actor_name, u.email AS actor_email
FROM audit_log_entries ale
LEFT JOIN users u ON ale.actor_type = 'user' AND u.id = ale.actor_id
WHERE (sqlc.arg(target_entity)::text = '' OR ale.target_entity = sqlc.arg(target_entity)::text)
  AND (sqlc.arg(action_filter)::text = '' OR ale.action ILIKE '%' || sqlc.arg(action_filter)::text || '%')
  AND (sqlc.arg(actor_type_filter)::text = '' OR ale.actor_type = sqlc.arg(actor_type_filter)::text)
  AND ale.created_at >= sqlc.arg(period_start)::timestamptz
  AND ale.created_at < sqlc.arg(period_end)::timestamptz
ORDER BY ale.created_at DESC
LIMIT sqlc.arg(row_limit) OFFSET sqlc.arg(row_offset);

-- name: ListAuditLogTargetEntities :many
-- Distinct target_entity values seen so far, to populate the filter dropdown.
SELECT DISTINCT target_entity FROM audit_log_entries ORDER BY target_entity;
