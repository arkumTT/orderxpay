-- Section 4.8 (revised): the platform's blended commission rate is composed
-- of three separately-tunable components instead of one opaque number — a
-- PSP collection fee (known per-transaction), a PSP payout fee (known only
-- per settlement batch), and OrderxPay's own margin — so admins can react
-- to a PSP pricing change without hand-deriving a new blended figure, and
-- merchants can see what their rate is built from. commission_bps remains
-- the single number invoice creation and checkout read (Section 5.1) — it's
-- still stored directly, just now constrained to equal the sum of its parts
-- rather than being the only thing admins type in.
--
-- Defaults here (200 + 100 + 100 = 400) intentionally match the one
-- existing global fee rule (commission_bps = 400) so the CHECK constraint
-- below is satisfiable without a manual backfill.
ALTER TABLE fee_rules
  ADD COLUMN collection_fee_bps int NOT NULL DEFAULT 200 CHECK (collection_fee_bps >= 0),
  ADD COLUMN payout_fee_bps int NOT NULL DEFAULT 100 CHECK (payout_fee_bps >= 0),
  ADD COLUMN margin_bps int NOT NULL DEFAULT 100 CHECK (margin_bps >= 0),
  ADD CONSTRAINT fee_rules_commission_bps_matches_components
    CHECK (commission_bps = collection_fee_bps + payout_fee_bps + margin_bps);

-- Merchant-controlled, parallel to service_charge_allocation above: whether
-- the merchant absorbs the payout-fee component at settlement (default) or
-- folds it into their blended rate instead (covered by whichever
-- Customer/Merchant/Split choice already applies to the collection fee).
-- NOTE: this column is honestly just a stored preference for now — the
-- settlement engine (Section 7.2) doesn't yet branch on it; see
-- Decisions_Log-equivalent context in the PR description.
ALTER TABLE merchants
  ADD COLUMN payout_fee_absorption text NOT NULL DEFAULT 'merchant_absorbed'
    CHECK (payout_fee_absorption IN ('merchant_absorbed', 'blended_into_rate'));
