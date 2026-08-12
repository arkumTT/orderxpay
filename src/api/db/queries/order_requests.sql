-- name: CreateOrderRequest :one
INSERT INTO order_requests (merchant_id, customer_contact, requested_items)
VALUES ($1, $2, $3)
RETURNING *;

-- name: GetOrderRequest :one
SELECT * FROM order_requests WHERE id = $1;

-- name: ListPendingOrderRequestsByMerchant :many
SELECT * FROM order_requests
WHERE merchant_id = $1 AND status = 'pending'
ORDER BY created_at;

-- name: SetOrderRequestStatus :one
UPDATE order_requests
SET status = $2, decline_reason = $3
WHERE id = $1
RETURNING *;
