-- name: CreateConversation :one
INSERT INTO conversations (merchant_id, customer_contact, channel, direction, message_type, template_id, consent)
VALUES ($1, $2, $3, $4, $5, $6, $7)
RETURNING *;

-- name: ListConversationsByMerchant :many
SELECT * FROM conversations
WHERE merchant_id = $1 AND customer_contact = $2
ORDER BY created_at DESC
LIMIT $3;
