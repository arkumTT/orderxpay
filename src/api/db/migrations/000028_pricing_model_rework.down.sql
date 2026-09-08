ALTER TABLE settlements DROP COLUMN withdrawal_fee_pesewas;

ALTER TABLE merchants
  ADD COLUMN payout_fee_absorption text NOT NULL DEFAULT 'merchant_absorbed'
    CHECK (payout_fee_absorption IN ('merchant_absorbed', 'blended_into_rate'));

-- The up migration's fold of payout_fee_bps into margin_bps is lossy, so
-- the column comes back at zero rather than guessing at a split: that keeps
-- commission_bps = collection + payout + margin true for every existing row
-- without changing anyone's blended rate on the way back down.
ALTER TABLE fee_rules
  DROP CONSTRAINT fee_rules_margin_cap_not_below_floor,
  DROP CONSTRAINT fee_rules_commission_bps_matches_components,
  DROP COLUMN withdrawal_fee_waiver_pesewas,
  DROP COLUMN withdrawal_fee_bank_pesewas,
  DROP COLUMN withdrawal_fee_momo_pesewas,
  DROP COLUMN margin_cap_pesewas,
  DROP COLUMN margin_floor_pesewas,
  ALTER COLUMN collection_fee_bps SET DEFAULT 200,
  ALTER COLUMN margin_bps SET DEFAULT 100,
  ADD COLUMN payout_fee_bps int NOT NULL DEFAULT 0 CHECK (payout_fee_bps >= 0),
  ADD CONSTRAINT fee_rules_commission_bps_matches_components
    CHECK (commission_bps = collection_fee_bps + payout_fee_bps + margin_bps);
