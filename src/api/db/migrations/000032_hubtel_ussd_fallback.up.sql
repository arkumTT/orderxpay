-- Section 4.5/9's USSD fallback: a customer who can't complete Paystack's
-- hosted checkout at all (no smartphone, no data, no browser) gets a
-- USSD/PIN prompt sent straight to their phone via Hubtel instead — see
-- internal/hubtel's package doc comment for what's confirmed about that
-- integration and what isn't (no Hubtel account exists yet to verify
-- against).
--
-- payments.provider distinguishes which PSP actually handled a given
-- payment — every payment before this migration is implicitly Paystack,
-- which the backfill below makes explicit rather than leaving inferred.
-- psp_reference is reused for Hubtel's ClientReference (same role: the
-- PSP's own idempotency/lookup key for this attempt), so
-- creditSuccessfulPayment's existing lookup-by-reference logic works for
-- both providers unchanged — only provider needed adding.
ALTER TABLE payments ADD COLUMN provider text NOT NULL DEFAULT 'paystack'
  CHECK (provider IN ('paystack', 'hubtel'));
ALTER TABLE payments ALTER COLUMN provider DROP DEFAULT;

-- Feature flag (Section 7.4) — off for everyone until a real Hubtel
-- account exists and this has been verified against it. See
-- feature_flags' own migration (000008) for the mechanism: enabled_
-- globally plus a per-merchant opt-in list for a staged rollout.
INSERT INTO feature_flags (key, name, description) VALUES
  ('hubtel_ussd_fallback', 'Hubtel USSD Fallback',
   'Sends a USSD/PIN payment prompt via Hubtel to a customer''s phone as a fallback when they can''t complete the ordinary Paystack checkout page (no smartphone, no data). UNVERIFIED — no Hubtel account exists yet to test against; see internal/hubtel''s doc comment. Do not enable before confirming the integration against a real account.');
