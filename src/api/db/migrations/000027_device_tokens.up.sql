-- Section 4.10 Phase 2: FCM registration tokens for push notifications —
-- Android only for now (see internal/fcm's doc comment on why iOS is
-- deferred). A merchant can have several active tokens at once (owner +
-- staff phones, or a reinstalled app before the old token expires), so
-- this is a one-to-many table keyed by merchant_id, not a column on
-- merchants. fcm_token is unique on its own (not per-merchant) because a
-- token that resurfaces under a different merchant means the previous
-- registration is stale (e.g. staff account reused on a different
-- merchant's test device) — upserting on token replaces it outright.
CREATE TABLE device_tokens (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  fcm_token   text NOT NULL UNIQUE,
  platform    text NOT NULL DEFAULT 'android' CHECK (platform IN ('android', 'ios')),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER device_tokens_set_updated_at BEFORE UPDATE ON device_tokens
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX device_tokens_merchant_id_idx ON device_tokens(merchant_id);
