-- name: FindDuplicateGhanaCardFlags :many
-- One row per merchant that shares a Ghana Card number with at least one
-- other merchant's KYC submission (any status — even a rejected submission
-- reusing someone else's card number is a real signal).
SELECT
  s.merchant_id,
  s.ghana_card_number,
  string_agg(DISTINCT m2.business_name, ', ')::text AS other_merchants
FROM kyc_submissions s
JOIN kyc_submissions s2 ON s2.ghana_card_number = s.ghana_card_number AND s2.merchant_id != s.merchant_id
JOIN merchants m2 ON m2.id = s2.merchant_id
GROUP BY s.merchant_id, s.ghana_card_number;

-- name: FindVelocitySpikes :many
-- Flags a merchant whose trailing-24h invoice count or value is both above
-- a floor (so a brand-new merchant's first few invoices don't trip it) and
-- a multiple of their own trailing 7-day daily average (so an
-- already-high-volume merchant isn't flagged just for staying busy).
WITH today AS (
  SELECT merchant_id, COUNT(*) AS cnt, COALESCE(SUM(total_pesewas), 0)::bigint AS val
  FROM invoices
  WHERE created_at >= now() - interval '24 hours'
    AND status != 'draft'
  GROUP BY merchant_id
),
baseline AS (
  SELECT merchant_id,
    COUNT(*)::float8 / 7 AS avg_cnt,
    COALESCE(SUM(total_pesewas), 0)::float8 / 7 AS avg_val
  FROM invoices
  WHERE created_at >= now() - interval '8 days'
    AND created_at < now() - interval '24 hours'
    AND status != 'draft'
  GROUP BY merchant_id
)
SELECT
  t.merchant_id,
  t.cnt AS today_count,
  t.val AS today_value_pesewas,
  COALESCE(b.avg_cnt, 0)::float8 AS baseline_avg_count,
  COALESCE(b.avg_val, 0)::float8 AS baseline_avg_value_pesewas
FROM today t
LEFT JOIN baseline b ON b.merchant_id = t.merchant_id
WHERE
  (t.cnt >= 5 AND (COALESCE(b.avg_cnt, 0) = 0 OR t.cnt::float8 > b.avg_cnt * 3))
  OR
  (t.val >= 500000 AND (COALESCE(b.avg_val, 0) = 0 OR t.val::float8 > b.avg_val * 3));

-- name: CreateRiskFlag :exec
-- Silently skipped when an identical open flag already exists
-- (risk_flags_dedupe_open) — a scan re-run should never spam duplicates.
INSERT INTO risk_flags (merchant_id, flag_type, dedupe_key, details)
VALUES ($1, $2, $3, $4)
ON CONFLICT (merchant_id, flag_type, dedupe_key) WHERE status = 'open' DO NOTHING;

-- name: GetRiskFlag :one
SELECT * FROM risk_flags WHERE id = $1;

-- name: ListRiskFlagsByMerchant :many
-- Backs the Section 7.1 merchant detail view's "flags" panel.
SELECT * FROM risk_flags WHERE merchant_id = $1 ORDER BY created_at DESC;

-- name: ListRiskFlagsAdmin :many
SELECT r.*, m.business_name AS merchant_business_name
FROM risk_flags r
JOIN merchants m ON m.id = r.merchant_id
WHERE (sqlc.arg(status_filter)::text = '' OR r.status = sqlc.arg(status_filter)::text)
ORDER BY r.created_at DESC
LIMIT sqlc.arg(row_limit) OFFSET sqlc.arg(row_offset);

-- name: ResolveRiskFlag :one
UPDATE risk_flags
SET status = sqlc.arg(status), resolution_notes = sqlc.arg(resolution_notes),
    reviewed_by = sqlc.arg(reviewed_by), reviewed_at = now()
WHERE id = sqlc.arg(id)
RETURNING *;
