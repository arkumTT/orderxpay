-- Section 7.7/7.2: the gap the Fee Architecture brief names under "Refund
-- and chargeback clawback" — RefundTransaction (000006) reverses the
-- charge with Paystack and records it on the payment, but says nothing
-- about who covers it once the merchant was already paid out for that
-- money via a completed settlement. Once a payment's settlement_id is set,
-- the merchant's share of it left OrderxPay's balance for good (Phase 1
-- payouts are manual, executed off-platform) — a clawback deducted from
-- the merchant's *next* settlement is the only way to recover it.
--
-- One row per refund that lands on an already-settled payment. amount_
-- pesewas is the merchant's entitled share of the refund, not the whole
-- refund — OrderxPay's own commission on that slice was never paid to the
-- merchant in the first place, so it isn't owed back — fixed at creation
-- time so a later fee-rule change can't retroactively change what's owed.
-- applied_settlement_id stays NULL until a future settlement run actually
-- deducts it; see GenerateSettlement's handling of this table.
CREATE TABLE settlement_clawbacks (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id           uuid NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  payment_id            uuid NOT NULL REFERENCES payments(id) ON DELETE CASCADE,
  dispute_id            uuid REFERENCES disputes(id) ON DELETE SET NULL,
  amount_pesewas        bigint NOT NULL CHECK (amount_pesewas > 0),
  reason                text NOT NULL,
  applied_settlement_id uuid REFERENCES settlements(id) ON DELETE SET NULL,
  created_at            timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX settlement_clawbacks_merchant_id_idx ON settlement_clawbacks(merchant_id);
-- GenerateSettlement's lookup: a merchant's outstanding (unapplied) debt,
-- oldest first.
CREATE INDEX settlement_clawbacks_outstanding_idx
  ON settlement_clawbacks(merchant_id, created_at) WHERE applied_settlement_id IS NULL;

-- Section 7.2: how much of this settlement's payout was withheld to repay
-- outstanding clawbacks, so a payout that looks smaller than the period's
-- own collections is explained on the record itself rather than looking
-- like a miscalculation.
ALTER TABLE settlements
  ADD COLUMN clawback_pesewas bigint NOT NULL DEFAULT 0
    CHECK (clawback_pesewas >= 0);
