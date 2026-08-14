-- name: CreateSettlement :one
INSERT INTO settlements (merchant_id, period_start, period_end, gross_collections_pesewas, psp_fees_pesewas, commission_pesewas, net_payout_pesewas)
VALUES ($1, $2, $3, $4, $5, $6, $7)
RETURNING *;

-- name: ListSettlementsByMerchant :many
SELECT * FROM settlements WHERE merchant_id = $1 ORDER BY period_start DESC;

-- name: SetSettlementStatus :one
UPDATE settlements SET status = $2 WHERE id = $1
RETURNING *;

-- name: GetSettlement :one
SELECT * FROM settlements WHERE id = $1;

-- name: ListSettlementsAdmin :many
-- Cross-merchant view backing the Back Office 7.2 landing page — the
-- per-merchant ListSettlementsByMerchant above stays as-is for the merchant
-- detail page's drill-down.
SELECT s.*, m.business_name AS merchant_business_name
FROM settlements s
JOIN merchants m ON m.id = s.merchant_id
WHERE (sqlc.arg(status_filter)::text = '' OR s.status = sqlc.arg(status_filter)::text)
ORDER BY s.created_at DESC
LIMIT sqlc.arg(row_limit) OFFSET sqlc.arg(row_offset);

-- name: ComputeSettlementAggregate :one
-- Section 7.2 batch-run reconciliation: sums every not-yet-settled
-- successful payment for the merchant in [period_start, period_end), and
-- prorates each invoice's commission/merchant-entitlement by how much of
-- that invoice was actually collected in the period — so a partially paid
-- invoice settles correctly on whichever payment(s) landed in this window,
-- without ever needing to touch a payment already claimed by an earlier
-- settlement (p.settlement_id IS NULL).
SELECT
  COALESCE(SUM(p.amount_pesewas), 0)::bigint AS gross_collections_pesewas,
  COALESCE(SUM(p.psp_fee_pesewas), 0)::bigint AS psp_fees_pesewas,
  COALESCE(SUM(i.commission_pesewas * p.amount_pesewas / NULLIF(i.total_pesewas, 0)), 0)::bigint AS commission_pesewas,
  COALESCE(SUM(
    (i.subtotal_pesewas + i.service_charge_pesewas
      + CASE WHEN i.delivery_fee_handling = 'bundled' THEN COALESCE(i.delivery_fee_pesewas, 0) ELSE 0 END
      - i.commission_pesewas
    ) * p.amount_pesewas / NULLIF(i.total_pesewas, 0)
  ), 0)::bigint AS net_payout_pesewas,
  COUNT(*)::bigint AS payment_count
FROM payments p
JOIN invoices i ON i.id = p.invoice_id
WHERE i.merchant_id = sqlc.arg(merchant_id)
  AND p.status = 'success'
  AND p.settlement_id IS NULL
  AND p.paid_at >= sqlc.arg(period_start)::timestamptz
  AND p.paid_at < sqlc.arg(period_end)::timestamptz;

-- name: MarkPaymentsSettled :exec
-- Stamps every payment just aggregated into ComputeSettlementAggregate with
-- the resulting settlement's id — must run with the exact same filter, in
-- the same transaction, or a payment could be double-counted by a later run.
UPDATE payments p
SET settlement_id = sqlc.arg(settlement_id)
FROM invoices i
WHERE p.invoice_id = i.id
  AND i.merchant_id = sqlc.arg(merchant_id)
  AND p.status = 'success'
  AND p.settlement_id IS NULL
  AND p.paid_at >= sqlc.arg(period_start)::timestamptz
  AND p.paid_at < sqlc.arg(period_end)::timestamptz;
