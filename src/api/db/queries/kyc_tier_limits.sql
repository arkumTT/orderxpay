-- name: ListKYCTierLimits :many
SELECT * FROM kyc_tier_limits ORDER BY tier;

-- name: GetKYCTierLimit :one
SELECT * FROM kyc_tier_limits WHERE tier = $1;

-- name: UpdateKYCTierLimit :one
-- NULL on any column means "no cap" — the enforcement path skips an unset
-- limit rather than treating it as zero.
UPDATE kyc_tier_limits
SET per_transaction_pesewas = sqlc.arg(per_transaction_pesewas),
    daily_pesewas = sqlc.arg(daily_pesewas),
    cumulative_pesewas = sqlc.arg(cumulative_pesewas)
WHERE tier = sqlc.arg(tier)
RETURNING *;

-- name: GetMerchantVolume :one
-- Collected volume for limit checks, measured on successful payments rather
-- than invoice totals: an invoice that was raised but never paid moved no
-- money and must not consume a merchant's headroom.
--
-- Deliberately gross, not net of refunds — otherwise a merchant could
-- refund their way back under a cap and transact the same money twice. The
-- daily window is a plain UTC calendar day, which is Ghana local time
-- year-round (UTC+0, no DST).
SELECT
  COALESCE(SUM(p.amount_pesewas) FILTER (
    WHERE p.paid_at >= date_trunc('day', now())
  ), 0)::bigint AS today_pesewas,
  COALESCE(SUM(p.amount_pesewas), 0)::bigint AS cumulative_pesewas
FROM payments p
JOIN invoices i ON i.id = p.invoice_id
WHERE i.merchant_id = $1 AND p.status = 'success';
