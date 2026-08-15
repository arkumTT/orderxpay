-- Section 7.4: feature flags for rolling a new module out to a subset of
-- merchants before flipping it on platform-wide. Flags are seeded here
-- (like permissions/roles) rather than created ad hoc from the Back
-- Office — a flag key only means something if code actually gates on it,
-- so the set of keys is a deploy-time concern. The Back Office manages
-- enablement (global toggle + per-merchant opt-in), not the key itself.
CREATE TABLE feature_flags (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key              text NOT NULL UNIQUE,
  name             text NOT NULL,
  description      text,
  enabled_globally boolean NOT NULL DEFAULT false,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER feature_flags_set_updated_at BEFORE UPDATE ON feature_flags
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- A merchant "has" a flag if enabled_globally is true OR they're listed
-- here — the subset-rollout mechanism ahead of a global flip.
CREATE TABLE feature_flag_merchants (
  feature_flag_id uuid NOT NULL REFERENCES feature_flags(id) ON DELETE CASCADE,
  merchant_id     uuid NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  created_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (feature_flag_id, merchant_id)
);

INSERT INTO feature_flags (key, name, description) VALUES
  ('ussd_payments', 'USSD Payments', 'Section 4.5/10 — USSD payment path for feature-phone customers'),
  ('whatsapp_catalog_sync', 'WhatsApp Catalog Sync', 'Section 6.2 — sync a merchant''s catalog into their WhatsApp Business catalog');
