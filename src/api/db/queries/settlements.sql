-- name: CreateSettlement :one
INSERT INTO settlements (merchant_id, period_start, period_end, gross_collections_pesewas, psp_fees_pesewas, commission_pesewas, net_payout_pesewas)
VALUES ($1, $2, $3, $4, $5, $6, $7)
RETURNING *;

-- name: ListSettlementsByMerchant :many
SELECT * FROM settlements WHERE merchant_id = $1 ORDER BY period_start DESC;

-- name: SetSettlementStatus :one
UPDATE settlements SET status = $2 WHERE id = $1
RETURNING *;
