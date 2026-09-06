-- name: UpsertCustomer :one
-- Best-effort auto-save (called after every invoice send) and the
-- manual "+ Add Customer" path share this same query — both are really
-- "remember this contact, keeping whatever name we already know unless
-- a better one just showed up." COALESCE keeps an existing name intact
-- when this particular call doesn't have one (EXCLUDED.name NULL).
INSERT INTO customers (merchant_id, contact, name)
VALUES ($1, $2, $3)
ON CONFLICT (merchant_id, contact) DO UPDATE
SET name = COALESCE(EXCLUDED.name, customers.name), updated_at = now()
RETURNING *;

-- name: ListCustomers :many
SELECT * FROM customers WHERE merchant_id = $1 ORDER BY updated_at DESC;

-- name: GetCustomer :one
SELECT * FROM customers WHERE id = $1;

-- name: UpdateCustomer :execrows
-- Ownership enforced in the WHERE clause, same pattern as
-- UpdateMerchantLocation — the route path only carries the customer's
-- own id, not the merchant id.
UPDATE customers SET name = $3, contact = $4, updated_at = now()
WHERE id = $1 AND merchant_id = $2;

-- name: DeleteCustomer :execrows
DELETE FROM customers WHERE id = $1 AND merchant_id = $2;
