-- name: GetGlobalFeeRule :one
SELECT * FROM fee_rules WHERE merchant_id IS NULL;

-- name: GetFeeRuleByMerchant :one
SELECT * FROM fee_rules WHERE merchant_id = $1;

-- name: UpsertGlobalFeeRule :one
-- commission_bps is derived server-side (collection + margin) so it can never
-- drift from what the components actually add up to — every other reader
-- (invoice engine, checkout) still just reads the one blended number.
INSERT INTO fee_rules (
  merchant_id, collection_fee_bps, margin_bps, commission_bps, allocation_type,
  margin_floor_pesewas, margin_cap_pesewas,
  withdrawal_fee_momo_pesewas, withdrawal_fee_bank_pesewas, withdrawal_fee_waiver_pesewas
)
VALUES (
  NULL, sqlc.arg(collection_fee_bps), sqlc.arg(margin_bps),
  sqlc.arg(collection_fee_bps)::int + sqlc.arg(margin_bps)::int,
  sqlc.arg(allocation_type),
  sqlc.arg(margin_floor_pesewas), sqlc.arg(margin_cap_pesewas),
  sqlc.arg(withdrawal_fee_momo_pesewas), sqlc.arg(withdrawal_fee_bank_pesewas),
  sqlc.arg(withdrawal_fee_waiver_pesewas)
)
ON CONFLICT ((1)) WHERE merchant_id IS NULL DO UPDATE
  SET collection_fee_bps = EXCLUDED.collection_fee_bps,
      margin_bps = EXCLUDED.margin_bps,
      commission_bps = EXCLUDED.commission_bps,
      allocation_type = EXCLUDED.allocation_type,
      margin_floor_pesewas = EXCLUDED.margin_floor_pesewas,
      margin_cap_pesewas = EXCLUDED.margin_cap_pesewas,
      withdrawal_fee_momo_pesewas = EXCLUDED.withdrawal_fee_momo_pesewas,
      withdrawal_fee_bank_pesewas = EXCLUDED.withdrawal_fee_bank_pesewas,
      withdrawal_fee_waiver_pesewas = EXCLUDED.withdrawal_fee_waiver_pesewas
RETURNING *;

-- name: UpsertMerchantFeeRule :one
INSERT INTO fee_rules (
  merchant_id, collection_fee_bps, margin_bps, commission_bps, allocation_type,
  margin_floor_pesewas, margin_cap_pesewas,
  withdrawal_fee_momo_pesewas, withdrawal_fee_bank_pesewas, withdrawal_fee_waiver_pesewas
)
VALUES (
  sqlc.arg(merchant_id), sqlc.arg(collection_fee_bps), sqlc.arg(margin_bps),
  sqlc.arg(collection_fee_bps)::int + sqlc.arg(margin_bps)::int,
  sqlc.arg(allocation_type),
  sqlc.arg(margin_floor_pesewas), sqlc.arg(margin_cap_pesewas),
  sqlc.arg(withdrawal_fee_momo_pesewas), sqlc.arg(withdrawal_fee_bank_pesewas),
  sqlc.arg(withdrawal_fee_waiver_pesewas)
)
ON CONFLICT (merchant_id) WHERE merchant_id IS NOT NULL DO UPDATE
  SET collection_fee_bps = EXCLUDED.collection_fee_bps,
      margin_bps = EXCLUDED.margin_bps,
      commission_bps = EXCLUDED.commission_bps,
      allocation_type = EXCLUDED.allocation_type,
      margin_floor_pesewas = EXCLUDED.margin_floor_pesewas,
      margin_cap_pesewas = EXCLUDED.margin_cap_pesewas,
      withdrawal_fee_momo_pesewas = EXCLUDED.withdrawal_fee_momo_pesewas,
      withdrawal_fee_bank_pesewas = EXCLUDED.withdrawal_fee_bank_pesewas,
      withdrawal_fee_waiver_pesewas = EXCLUDED.withdrawal_fee_waiver_pesewas
RETURNING *;

-- name: ListMerchantFeeRuleOverrides :many
SELECT f.*, m.business_name AS merchant_business_name
FROM fee_rules f
JOIN merchants m ON m.id = f.merchant_id
WHERE f.merchant_id IS NOT NULL
ORDER BY m.business_name;

-- name: DeleteMerchantFeeRule :exec
DELETE FROM fee_rules WHERE merchant_id = $1;
