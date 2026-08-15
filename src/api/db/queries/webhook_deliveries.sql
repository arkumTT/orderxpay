-- name: CreateWebhookDelivery :exec
INSERT INTO webhook_deliveries (provider, event_type, reference, signature_valid, processed_ok, error_message)
VALUES ($1, $2, $3, $4, $5, $6);

-- name: ListWebhookDeliveries :many
SELECT * FROM webhook_deliveries ORDER BY received_at DESC LIMIT $1 OFFSET $2;
