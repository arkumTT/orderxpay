-- name: GetGlobalFeeRule :one
SELECT * FROM fee_rules WHERE merchant_id IS NULL;

-- name: GetFeeRuleByMerchant :one
SELECT * FROM fee_rules WHERE merchant_id = $1;

-- name: UpsertGlobalFeeRule :one
INSERT INTO fee_rules (merchant_id, commission_bps, allocation_type)
VALUES (NULL, $1, $2)
ON CONFLICT ((1)) WHERE merchant_id IS NULL DO UPDATE
  SET commission_bps = EXCLUDED.commission_bps,
      allocation_type = EXCLUDED.allocation_type
RETURNING *;

-- name: UpsertMerchantFeeRule :one
INSERT INTO fee_rules (merchant_id, commission_bps, allocation_type)
VALUES ($1, $2, $3)
ON CONFLICT (merchant_id) WHERE merchant_id IS NOT NULL DO UPDATE
  SET commission_bps = EXCLUDED.commission_bps,
      allocation_type = EXCLUDED.allocation_type
RETURNING *;
