-- Section 7.2: the settlement engine needs to know, per invoice, the full
-- commission OrderxPay is owed (not just the customer-visible service
-- charge portion — merchant_only/split allocations mean part or all of the
-- commission is absorbed out of the merchant's own proceeds instead of
-- charged on top). Persisted at invoice-creation time alongside the other
-- fee-computation fields, for the same reason: a later commission-rate
-- change must never retroactively change an issued invoice.
ALTER TABLE invoices ADD COLUMN commission_pesewas bigint NOT NULL DEFAULT 0 CHECK (commission_pesewas >= 0);

-- Paystack reports the fee it deducted on each successful charge — captured
-- so Section 7.5's cost-vs-revenue reporting has real PSP fee data instead
-- of an estimate.
ALTER TABLE payments ADD COLUMN psp_fee_pesewas bigint NOT NULL DEFAULT 0 CHECK (psp_fee_pesewas >= 0);

-- Ties a successful payment to the settlement batch it was paid out in, so
-- generating a settlement for a period can never double-pay a payment
-- already covered by an earlier batch (Section 7.2 payout ledger).
ALTER TABLE payments ADD COLUMN settlement_id uuid REFERENCES settlements(id) ON DELETE SET NULL;
CREATE INDEX payments_settlement_id_idx ON payments(settlement_id);
