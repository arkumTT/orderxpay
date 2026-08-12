-- name: CreatePayment :one
INSERT INTO payments (invoice_id, psp_reference, method, amount_pesewas, status)
VALUES ($1, $2, $3, $4, $5)
RETURNING *;

-- name: GetPaymentByPSPReference :one
SELECT * FROM payments WHERE psp_reference = $1;

-- name: ListPaymentsByInvoice :many
SELECT * FROM payments WHERE invoice_id = $1 ORDER BY created_at;

-- name: SetPaymentStatus :one
UPDATE payments
SET status = $2, paid_at = CASE WHEN $2 = 'success' THEN now() ELSE paid_at END
WHERE id = $1
RETURNING *;

-- name: SumSuccessfulPaymentsByInvoice :one
SELECT COALESCE(SUM(amount_pesewas), 0)::bigint AS total_paid_pesewas
FROM payments
WHERE invoice_id = $1 AND status = 'success';
