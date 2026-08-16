-- name: CreateMerchant :one
INSERT INTO merchants (business_name, category, phone)
VALUES ($1, $2, $3)
RETURNING *;

-- name: GetMerchant :one
SELECT * FROM merchants WHERE id = $1;

-- name: GetMerchantByPhone :one
SELECT * FROM merchants WHERE phone = $1;

-- name: ListMerchants :many
SELECT * FROM merchants
WHERE (@status_filter::text = '' OR status = @status_filter::text)
ORDER BY created_at DESC
LIMIT $1 OFFSET $2;

-- name: UpdateMerchantKYCTier :one
UPDATE merchants SET kyc_tier = $2 WHERE id = $1
RETURNING *;

-- name: UpdateMerchantStatus :one
UPDATE merchants SET status = $2 WHERE id = $1
RETURNING *;

-- name: UpdateMerchantFeeSettings :one
UPDATE merchants
SET service_charge_allocation = $2,
    service_charge_split_bps = $3,
    payout_fee_absorption = $4
WHERE id = $1
RETURNING *;

-- name: UpdateMerchantWhatsAppSettings :one
UPDATE merchants
SET whatsapp_auto_reply_enabled = $2,
    whatsapp_greeting_message = $3
WHERE id = $1
RETURNING *;
