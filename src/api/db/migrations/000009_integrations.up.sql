-- Section 7.3: one row per named integration slot. `built` distinguishes
-- Paystack (the one integration this codebase actually has code for) from
-- the other four, which are configuration placeholders — the Back Office
-- can record notes/vendor decisions for them, but never a fake "configured"
-- status, since no code anywhere gates on their credentials.
CREATE TABLE integrations (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_key       text NOT NULL UNIQUE CHECK (provider_key IN ('paystack', 'whatsapp_bsp', 'sms_email', 'ussd_aggregator', 'gra_evat')),
  category           text NOT NULL,
  built              boolean NOT NULL DEFAULT false,
  -- secret_value is write-only from the API's perspective (Section 7.3:
  -- "never displayed in plaintext after entry") — ListIntegrations must
  -- never return it, only whether it's set and when/who last changed it.
  secret_value       text,
  secret_updated_at  timestamptz,
  secret_updated_by  uuid REFERENCES users(id) ON DELETE SET NULL,
  notes              text,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER integrations_set_updated_at BEFORE UPDATE ON integrations
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

INSERT INTO integrations (provider_key, category, built) VALUES
  ('paystack', 'Payment Gateway / PSP', true),
  ('whatsapp_bsp', 'WhatsApp Business Solution Provider', false),
  ('sms_email', 'SMS / Email Provider', false),
  ('ussd_aggregator', 'USSD Aggregator', false),
  ('gra_evat', 'GRA E-VAT Connector (optional)', false);

-- Append-only inbound-webhook log (Section 7.3's "webhook delivery logs") —
-- previously a failed/bad-signature webhook call only ever showed up in
-- stdout, nothing queryable.
CREATE TABLE webhook_deliveries (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider        text NOT NULL DEFAULT 'paystack',
  event_type      text,
  reference       text,
  signature_valid boolean NOT NULL,
  processed_ok    boolean NOT NULL,
  error_message   text,
  received_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX webhook_deliveries_received_at_idx ON webhook_deliveries(received_at DESC);

-- Section 4.11/9.4: the admin-maintained directory of verified delivery
-- providers and their deep-link parameters — the source delivery_options'
-- own provider_key/deep_link_template (Section 000001) are meant to be
-- drawn from, editable without a release. No FK from delivery_options to
-- here yet (that's the merchant-app side picking from this list, a
-- separate follow-up) — this migration only adds the admin-side catalog.
CREATE TABLE delivery_providers (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key                text NOT NULL UNIQUE,
  name               text NOT NULL,
  deep_link_template text NOT NULL,
  status             text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  notes              text,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER delivery_providers_set_updated_at BEFORE UPDATE ON delivery_providers
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Section 9.4: Bolt Send is the one provider the architecture doc confirms
-- as actually operating in Ghana for parcel delivery — Uber Connect and
-- Yango were both explicitly unconfirmed, so they aren't seeded as if
-- verified. More can be added for real through the admin UI.
INSERT INTO delivery_providers (key, name, deep_link_template, notes) VALUES
  ('bolt_send', 'Bolt Send', 'https://bolt.eu/send?pickup={pickup}&dropoff={dropoff}', 'Confirmed operating in Ghana for parcel delivery (Section 9.4) — deep-link parameter names are illustrative, verify against Bolt''s current API before going live.');
