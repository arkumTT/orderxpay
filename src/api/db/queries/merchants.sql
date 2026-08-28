-- name: CreateMerchant :one
INSERT INTO merchants (business_name, category, phone, username, email, password_hash)
VALUES ($1, $2, $3, $4, $5, $6)
RETURNING *;

-- name: GetMerchant :one
SELECT * FROM merchants WHERE id = $1;

-- name: GetMerchantByPhone :one
SELECT * FROM merchants WHERE phone = $1;

-- name: GetMerchantByEmail :one
SELECT * FROM merchants WHERE email = $1::text;

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

-- name: UpdateMerchantDeliveryEnabled :one
UPDATE merchants SET delivery_enabled = $2 WHERE id = $1
RETURNING *;

-- name: GetMerchantByWhatsAppPhoneNumberID :one
-- Attributes an inbound WhatsApp webhook to a merchant — see
-- internal/whatsapp and handlers/whatsapp.go.
SELECT * FROM merchants WHERE whatsapp_phone_number_id = $1::text;

-- name: UpdateMerchantWhatsAppPhoneNumberID :one
-- Admin-only provisioning step (Section 7.3): OrderxPay registers the
-- merchant's number under the platform WABA in Meta's console, then
-- records the resulting phone_number_id here.
UPDATE merchants SET whatsapp_phone_number_id = $2 WHERE id = $1
RETURNING *;

-- name: IncrementMerchantStorageUsed :one
-- Section 4.2: item photo uploads. delta is the file size in bytes — always
-- positive today (nothing decrements it yet; replacing/archiving an item's
-- photo leaves the old file's bytes counted, a known simplification for
-- this first pass).
UPDATE merchants SET storage_used_bytes = storage_used_bytes + $2 WHERE id = $1
RETURNING *;
