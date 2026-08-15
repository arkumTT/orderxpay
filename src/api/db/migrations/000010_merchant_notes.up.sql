-- Section 7.1 merchant detail view: "notes/flags from support or
-- compliance staff" — freeform annotations, distinct from the automated
-- risk_flags table.
CREATE TABLE merchant_notes (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  author_id   uuid NOT NULL REFERENCES users(id),
  body        text NOT NULL CHECK (length(body) > 0),
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX merchant_notes_merchant_id_idx ON merchant_notes(merchant_id);
