-- name: SearchInvoicesForSupport :many
-- Matches on invoice reference or customer phone — the two things a support
-- agent is handed on a call ("my order is ORD-1234" / "I paid with 024...").
SELECT i.*, m.business_name AS merchant_business_name, m.phone AS merchant_phone
FROM invoices i
JOIN merchants m ON m.id = i.merchant_id
WHERE i.status != 'draft'
  AND (i.reference ILIKE '%' || sqlc.arg(query)::text || '%'
       OR i.customer_contact ILIKE '%' || sqlc.arg(query)::text || '%')
ORDER BY i.created_at DESC
LIMIT 25;

-- name: SearchMerchantsForSupport :many
SELECT * FROM merchants
WHERE business_name ILIKE '%' || sqlc.arg(query)::text || '%'
   OR phone ILIKE '%' || sqlc.arg(query)::text || '%'
ORDER BY created_at DESC
LIMIT 25;

-- name: GetSupportTransaction :one
SELECT i.*, m.business_name AS merchant_business_name, m.phone AS merchant_phone
FROM invoices i
JOIN merchants m ON m.id = i.merchant_id
WHERE i.reference = sqlc.arg(reference)::text;
