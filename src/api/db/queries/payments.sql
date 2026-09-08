-- name: CreatePayment :one
-- paystack_subaccount_code is set only when this specific charge was split
-- at initialize time — null (the default) is the ordinary path, unchanged
-- from before split payments existed. provider defaults to 'paystack' at
-- the schema level (Paystack was the only provider before Hubtel USSD
-- existed) but is passed explicitly here so a Hubtel-initiated payment can
-- say so.
INSERT INTO payments (invoice_id, psp_reference, method, amount_pesewas, status, paystack_subaccount_code, provider)
VALUES (sqlc.arg(invoice_id), sqlc.arg(psp_reference), sqlc.arg(method), sqlc.arg(amount_pesewas), sqlc.arg(status), sqlc.arg(paystack_subaccount_code), sqlc.arg(provider))
RETURNING *;

-- name: GetPayment :one
SELECT * FROM payments WHERE id = $1;

-- name: GetPaymentByPSPReference :one
SELECT * FROM payments WHERE psp_reference = $1;

-- name: ListPaymentsByInvoice :many
SELECT * FROM payments WHERE invoice_id = $1 ORDER BY created_at;

-- name: SetPaymentStatus :one
UPDATE payments
SET status = $2, psp_fee_pesewas = $3, method = $4, paid_at = CASE WHEN $2 = 'success' THEN now() ELSE paid_at END
WHERE id = $1
RETURNING *;

-- name: SumSuccessfulPaymentsByInvoice :one
SELECT COALESCE(SUM(amount_pesewas), 0)::bigint AS total_paid_pesewas
FROM payments
WHERE invoice_id = $1 AND status = 'success';
