-- name: CreateDispute :one
INSERT INTO disputes (invoice_id, reason_category, description, created_by)
VALUES ($1, $2, $3, $4)
RETURNING *;

-- name: GetDispute :one
SELECT * FROM disputes WHERE id = $1;

-- name: ListDisputesAdmin :many
SELECT d.*, i.reference AS invoice_reference, i.customer_contact, m.business_name AS merchant_business_name
FROM disputes d
JOIN invoices i ON i.id = d.invoice_id
JOIN merchants m ON m.id = i.merchant_id
WHERE (sqlc.arg(status_filter)::text = '' OR d.status = sqlc.arg(status_filter)::text)
ORDER BY d.created_at DESC
LIMIT sqlc.arg(row_limit) OFFSET sqlc.arg(row_offset);

-- name: SetDisputeStatus :one
-- Non-terminal transition only (e.g. open -> investigating) — no
-- resolution fields; see ResolveDispute for the terminal transitions.
UPDATE disputes SET status = $2 WHERE id = $1
RETURNING *;

-- name: ResolveDispute :one
UPDATE disputes
SET status = sqlc.arg(status), resolution_notes = sqlc.arg(resolution_notes),
    refund_payment_id = sqlc.arg(refund_payment_id), refund_amount_pesewas = sqlc.arg(refund_amount_pesewas),
    resolved_by = sqlc.arg(resolved_by), resolved_at = now()
WHERE id = sqlc.arg(id)
RETURNING *;

-- name: AddPaymentRefund :one
UPDATE payments SET refunded_amount_pesewas = refunded_amount_pesewas + sqlc.arg(amount)
WHERE id = sqlc.arg(id)
RETURNING *;
