-- Section 7.7: a structured record of a customer complaint against an
-- invoice, tracked to resolution, with an optional refund through the PSP.
-- Logged by Back Office/support staff (Section 7.10) — the customer has no
-- account to self-report from, and the merchant hears about it first over
-- whatever channel they already use (Section 4.4), then support logs it.
CREATE TABLE disputes (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id            uuid NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
  reason_category       text NOT NULL CHECK (reason_category IN ('not_received', 'wrong_item', 'damaged', 'duplicate_charge', 'not_as_described', 'other')),
  description           text,
  status                text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'investigating', 'resolved_refunded', 'resolved_denied')),
  resolution_notes      text,
  refund_payment_id     uuid REFERENCES payments(id) ON DELETE SET NULL,
  refund_amount_pesewas bigint CHECK (refund_amount_pesewas IS NULL OR refund_amount_pesewas > 0),
  created_by            uuid REFERENCES users(id) ON DELETE SET NULL,
  resolved_by           uuid REFERENCES users(id) ON DELETE SET NULL,
  resolved_at           timestamptz,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER disputes_set_updated_at BEFORE UPDATE ON disputes
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX disputes_invoice_id_idx ON disputes(invoice_id);
CREATE INDEX disputes_status_idx ON disputes(status);

-- Tracks how much of a given successful payment has been refunded so far —
-- a separate running total rather than repurposing payments.status, since a
-- payment that's been refunded was still genuinely successful (that history
-- shouldn't be erased) and a partial refund needs to coexist with the rest
-- of the amount staying collected.
ALTER TABLE payments ADD COLUMN refunded_amount_pesewas bigint NOT NULL DEFAULT 0 CHECK (refunded_amount_pesewas >= 0);
ALTER TABLE payments ADD CONSTRAINT payments_refund_not_exceed_amount CHECK (refunded_amount_pesewas <= amount_pesewas);
