ALTER TABLE merchants DROP COLUMN payout_fee_absorption;

ALTER TABLE fee_rules DROP CONSTRAINT fee_rules_commission_bps_matches_components;
ALTER TABLE fee_rules
  DROP COLUMN collection_fee_bps,
  DROP COLUMN payout_fee_bps,
  DROP COLUMN margin_bps;
