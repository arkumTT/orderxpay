-- name: GetMerchantRevenueBreakdown :many
-- Section 7.5: one row per merchant for the selected period — LEFT JOINs
-- so a merchant with zero activity in the period still appears (with all
-- figures at 0), which is exactly what "active vs. dormant" needs to be
-- computed from in Go rather than a second query. Commission is prorated
-- by how much of each invoice was actually collected in the period, the
-- same pattern as the settlement engine's ComputeSettlementAggregate.
SELECT
  m.id AS merchant_id,
  m.business_name,
  m.status AS merchant_status,
  COALESCE(SUM(p.amount_pesewas), 0)::bigint AS gmv_pesewas,
  COALESCE(SUM(p.psp_fee_pesewas), 0)::bigint AS psp_fees_pesewas,
  COALESCE(SUM(i.commission_pesewas * p.amount_pesewas / NULLIF(i.total_pesewas, 0)), 0)::bigint AS commission_pesewas,
  COUNT(p.id)::bigint AS payment_count
FROM merchants m
LEFT JOIN invoices i ON i.merchant_id = m.id
LEFT JOIN payments p ON p.invoice_id = i.id
  AND p.status = 'success'
  AND p.paid_at >= sqlc.arg(period_start)::timestamptz
  AND p.paid_at < sqlc.arg(period_end)::timestamptz
GROUP BY m.id, m.business_name, m.status
ORDER BY gmv_pesewas DESC, m.business_name;

-- name: GetDailyRevenue :many
-- Daily time series for the same period — only days with at least one
-- successful payment (a table doesn't need zero-filled gap rows the way a
-- chart would).
SELECT
  DATE(p.paid_at) AS day,
  COALESCE(SUM(p.amount_pesewas), 0)::bigint AS gmv_pesewas,
  COALESCE(SUM(p.psp_fee_pesewas), 0)::bigint AS psp_fees_pesewas,
  COALESCE(SUM(i.commission_pesewas * p.amount_pesewas / NULLIF(i.total_pesewas, 0)), 0)::bigint AS commission_pesewas
FROM payments p
JOIN invoices i ON i.id = p.invoice_id
WHERE p.status = 'success'
  AND p.paid_at >= sqlc.arg(period_start)::timestamptz
  AND p.paid_at < sqlc.arg(period_end)::timestamptz
GROUP BY DATE(p.paid_at)
ORDER BY day;
