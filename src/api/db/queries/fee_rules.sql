-- name: GetGlobalFeeRule :one
SELECT * FROM fee_rules WHERE merchant_id IS NULL;

-- name: GetFeeRuleByMerchant :one
SELECT * FROM fee_rules WHERE merchant_id = $1;

-- name: UpsertGlobalFeeRule :one
-- commission_bps is derived server-side (sum of the three components) so it
-- can never drift from what the components actually add up to — every other
-- reader (invoice engine, checkout) still just reads the one blended number.
INSERT INTO fee_rules (merchant_id, collection_fee_bps, payout_fee_bps, margin_bps, commission_bps, allocation_type)
VALUES (NULL, $1, $2, $3, $1::int + $2::int + $3::int, $4)
ON CONFLICT ((1)) WHERE merchant_id IS NULL DO UPDATE
  SET collection_fee_bps = EXCLUDED.collection_fee_bps,
      payout_fee_bps = EXCLUDED.payout_fee_bps,
      margin_bps = EXCLUDED.margin_bps,
      commission_bps = EXCLUDED.commission_bps,
      allocation_type = EXCLUDED.allocation_type
RETURNING *;

-- name: UpsertMerchantFeeRule :one
INSERT INTO fee_rules (merchant_id, collection_fee_bps, payout_fee_bps, margin_bps, commission_bps, allocation_type)
VALUES ($1, $2, $3, $4, $2::int + $3::int + $4::int, $5)
ON CONFLICT (merchant_id) WHERE merchant_id IS NOT NULL DO UPDATE
  SET collection_fee_bps = EXCLUDED.collection_fee_bps,
      payout_fee_bps = EXCLUDED.payout_fee_bps,
      margin_bps = EXCLUDED.margin_bps,
      commission_bps = EXCLUDED.commission_bps,
      allocation_type = EXCLUDED.allocation_type
RETURNING *;

-- name: ListMerchantFeeRuleOverrides :many
SELECT f.*, m.business_name AS merchant_business_name
FROM fee_rules f
JOIN merchants m ON m.id = f.merchant_id
WHERE f.merchant_id IS NOT NULL
ORDER BY m.business_name;

-- name: DeleteMerchantFeeRule :exec
DELETE FROM fee_rules WHERE merchant_id = $1;
