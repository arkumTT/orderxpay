-- Section 7.6: a manual review queue fed by on-demand detection rules
-- (there's no job scheduler in this stack, so "Run scan" computes fresh
-- flags rather than a background worker running continuously). dedupe_key
-- is a stable, structured identity for what was detected (e.g. a Ghana
-- Card number, or a flagged calendar day) — separate from the
-- human-readable details text, which can be regenerated on every scan
-- without breaking the "don't re-flag the same thing" guarantee.
CREATE TABLE risk_flags (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id       uuid NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  flag_type         text NOT NULL CHECK (flag_type IN ('duplicate_ghana_card', 'velocity_spike')),
  dedupe_key        text NOT NULL,
  details           text NOT NULL,
  status            text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'dismissed', 'escalated')),
  resolution_notes  text,
  reviewed_by       uuid REFERENCES users(id) ON DELETE SET NULL,
  reviewed_at       timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER risk_flags_set_updated_at BEFORE UPDATE ON risk_flags
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX risk_flags_merchant_id_idx ON risk_flags(merchant_id);
CREATE INDEX risk_flags_status_idx ON risk_flags(status);

-- A scan re-run should never spam duplicate open flags for the same
-- merchant + rule + specific finding.
CREATE UNIQUE INDEX risk_flags_dedupe_open
  ON risk_flags(merchant_id, flag_type, dedupe_key)
  WHERE status = 'open';
