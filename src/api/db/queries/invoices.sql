-- name: CreateInvoice :one
INSERT INTO invoices (
  merchant_id, order_request_id, reference, customer_contact,
  subtotal_pesewas, service_charge_pesewas, service_charge_allocation, total_pesewas,
  delivery_option_id, delivery_address, delivery_fee_handling, delivery_fee_pesewas, expires_at,
  commission_pesewas, pickup_location_id
)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
RETURNING *;

-- name: CreateInvoiceLineItem :one
INSERT INTO invoice_line_items (invoice_id, item_id, description, unit_price_pesewas, quantity, line_total_pesewas)
VALUES ($1, $2, $3, $4, $5, $6)
RETURNING *;

-- name: GetInvoice :one
SELECT * FROM invoices WHERE id = $1;

-- name: GetInvoiceByReference :one
SELECT * FROM invoices WHERE reference = $1;

-- name: ListInvoiceLineItems :many
SELECT * FROM invoice_line_items WHERE invoice_id = $1;

-- name: ListInvoicesByMerchant :many
SELECT * FROM invoices
WHERE merchant_id = $1
  AND (@status_filter::text = '' OR status = @status_filter::text)
ORDER BY created_at DESC
LIMIT $2 OFFSET $3;

-- name: SetInvoiceStatus :one
UPDATE invoices SET status = $2 WHERE id = $1
RETURNING *;
