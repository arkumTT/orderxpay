-- name: ListIntegrations :many
SELECT * FROM integrations ORDER BY built DESC, category;

-- name: GetIntegration :one
SELECT * FROM integrations WHERE provider_key = $1;

-- name: SetIntegrationSecret :one
UPDATE integrations
SET secret_value = $2, secret_updated_at = now(), secret_updated_by = $3
WHERE provider_key = $1
RETURNING *;

-- name: UpdateIntegrationNotes :one
UPDATE integrations SET notes = $2
WHERE provider_key = $1
RETURNING *;
