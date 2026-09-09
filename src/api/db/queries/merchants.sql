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
-- Used by the Back Office tier override, which moves the tier without a
-- submission behind it and so leaves business_type alone.
UPDATE merchants SET kyc_tier = $2 WHERE id = $1
RETURNING *;

-- name: ApproveMerchantKYC :one
-- Used when a submission is approved: the tier and the fork that earned it
-- land together, so a Tier 2 merchant always carries business_type
-- 'registered' and the two can never drift apart.
UPDATE merchants
SET kyc_tier = sqlc.arg(kyc_tier), business_type = sqlc.arg(business_type)
WHERE id = sqlc.arg(id)
RETURNING *;

-- name: UpdateMerchantStatus :one
UPDATE merchants SET status = $2 WHERE id = $1
RETURNING *;

-- name: UpdateMerchantEmail :one
UPDATE merchants SET email = $2 WHERE id = $1
RETURNING *;

-- name: UpdateMerchantFeeSettings :one
UPDATE merchants
SET service_charge_allocation = $2,
    service_charge_split_bps = $3
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

-- name: UpdateMerchantWhatsAppCatalogID :one
-- Admin-only provisioning step (Section 6.2), same reasoning as
-- UpdateMerchantWhatsAppPhoneNumberID: an admin creates the catalog in
-- Meta Commerce Manager and connects it to the merchant's WhatsApp
-- Business Account, then records the resulting catalog_id here — no
-- merchant self-service path exists for this.
UPDATE merchants SET whatsapp_catalog_id = $2 WHERE id = $1
RETURNING *;

-- name: IncrementMerchantStorageUsed :one
-- Section 4.2: item photo uploads. delta is the file size in bytes — always
-- positive today (nothing decrements it yet; replacing/archiving an item's
-- photo leaves the old file's bytes counted, a known simplification for
-- this first pass).
UPDATE merchants SET storage_used_bytes = storage_used_bytes + $2 WHERE id = $1
RETURNING *;

-- name: UpdateMerchantPayoutAccount :one
-- account_name and verified_at travel together with the account details
-- they describe — never set independently, so a resolved name can never
-- outlive the account number it was resolved against. See
-- UpdateMerchantPayoutAccountParams' caller (SetPayoutAccount) for the
-- rule that clears them back to null whenever the account itself changes.
UPDATE merchants
SET payout_account_type = sqlc.arg(payout_account_type),
    payout_account_ref = sqlc.arg(payout_account_ref),
    payout_bank_code = sqlc.arg(payout_bank_code),
    payout_account_name = sqlc.arg(payout_account_name),
    payout_account_verified_at = sqlc.arg(payout_account_verified_at)
WHERE id = sqlc.arg(id)
RETURNING *;

-- name: UpdateMerchantSubaccountCode :one
-- Provisioning-only: records the Paystack subaccount created/updated
-- alongside a verified payout account (SetPayoutAccount in
-- payout_account.go). Never changes how any payment routes by itself —
-- see InitiateCheckoutPayment for the only place that reads this and
-- actually splits a charge.
UPDATE merchants SET paystack_subaccount_code = $2 WHERE id = $1
RETURNING *;
