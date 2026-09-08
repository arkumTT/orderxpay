-- Section 4.8, revising 000011. Two things that migration got wrong, both
-- surfaced while fixing the invoice fee calculation:
--
-- 1. payout_fee_bps modelled Paystack's payout cost as a percentage, but it
--    is flat: GHS 1 to a mobile money wallet, GHS 8 to a bank account. One
--    percentage cannot represent that at any scale — at 1%, a GHS 50
--    withdrawal bills GHS 0.50 against a GHS 1 cost (a loss), while a
--    GHS 5,000 withdrawal bills GHS 50 against the same GHS 1. It is
--    replaced by the flat withdrawal fees below.
--
-- 2. merchants.payout_fee_absorption let a merchant push the payout cost on
--    to the customer. A customer paying an invoice has no relationship with
--    the merchant's later withdrawal, and the settlement engine never
--    branched on the column — a stored preference with no behaviour behind
--    it.
--
-- Also adds the floor and cap that keep OrderxPay's own take viable at both
-- ends of the ticket range: 55 bps of a GHS 10 invoice is not worth
-- carrying, and 55 bps of a GHS 50,000 invoice is visible enough that the
-- merchant routes around the platform entirely. Only the margin is clamped,
-- never the PSP pass-through, so a capped invoice can still never cost more
-- to process than it charges.

-- Existing rows carry their blended rate forward rather than being silently
-- repriced: the retired payout component folds into margin, leaving
-- commission_bps (the only number that actually prices an invoice)
-- unchanged for every merchant already on the platform. Moving the live
-- rate to the new 195 + 55 default is a deliberate, separate decision made
-- through the Back Office, not a side effect of a schema change.
ALTER TABLE fee_rules DROP CONSTRAINT fee_rules_commission_bps_matches_components;

UPDATE fee_rules SET margin_bps = GREATEST(0, commission_bps - collection_fee_bps);
UPDATE fee_rules SET commission_bps = collection_fee_bps + margin_bps;

ALTER TABLE fee_rules DROP COLUMN payout_fee_bps;

-- margin_floor_pesewas / margin_cap_pesewas clamp OrderxPay's margin per
-- invoice. Zero means "no cap" for the cap and "no floor" for the floor.
-- Defaults are the recommended model: 1.95% pass-through + 0.55% margin,
-- floored at GHS 0.20 and capped at GHS 25.00.
ALTER TABLE fee_rules
  ALTER COLUMN collection_fee_bps SET DEFAULT 195,
  ALTER COLUMN margin_bps SET DEFAULT 55,
  ADD COLUMN margin_floor_pesewas bigint NOT NULL DEFAULT 20
    CHECK (margin_floor_pesewas >= 0),
  ADD COLUMN margin_cap_pesewas bigint NOT NULL DEFAULT 2500
    CHECK (margin_cap_pesewas >= 0),
  -- Flat, matching the PSP's own flat cost. Passed through to the merchant
  -- at withdrawal and waived entirely above the waiver threshold, which
  -- nudges merchants into batching — the behaviour that makes the flat cost
  -- cheap for everyone.
  ADD COLUMN withdrawal_fee_momo_pesewas bigint NOT NULL DEFAULT 100
    CHECK (withdrawal_fee_momo_pesewas >= 0),
  ADD COLUMN withdrawal_fee_bank_pesewas bigint NOT NULL DEFAULT 800
    CHECK (withdrawal_fee_bank_pesewas >= 0),
  ADD COLUMN withdrawal_fee_waiver_pesewas bigint NOT NULL DEFAULT 50000
    CHECK (withdrawal_fee_waiver_pesewas >= 0),
  ADD CONSTRAINT fee_rules_commission_bps_matches_components
    CHECK (commission_bps = collection_fee_bps + margin_bps),
  ADD CONSTRAINT fee_rules_margin_cap_not_below_floor
    CHECK (margin_cap_pesewas = 0 OR margin_cap_pesewas >= margin_floor_pesewas);

ALTER TABLE merchants DROP COLUMN payout_fee_absorption;

-- Section 7.2: the flat fee actually charged on this batch, recorded so a
-- settlement still reconciles years later even after the fee rule changes.
ALTER TABLE settlements
  ADD COLUMN withdrawal_fee_pesewas bigint NOT NULL DEFAULT 0
    CHECK (withdrawal_fee_pesewas >= 0);
