-- Section 4.10: real, persisted in-app alerts for the merchant — payment
-- received, a new order request awaiting confirmation, a payout settled,
-- or a KYC review decision. This is the in-app half of the section only;
-- push/SMS/WhatsApp delivery isn't built (no push provider, and SMS/
-- WhatsApp both depend on integrations this platform doesn't have yet —
-- see integrations.sms_email / whatsapp_bsp, both built = false).
CREATE TABLE notifications (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id   uuid NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  type          text NOT NULL CHECK (type IN ('payment_received', 'order_request_pending', 'payout_processed', 'kyc_status_change')),
  title         text NOT NULL,
  body          text NOT NULL,
  target_entity text,
  target_id     uuid,
  read_at       timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX notifications_merchant_id_created_at_idx ON notifications(merchant_id, created_at DESC);
