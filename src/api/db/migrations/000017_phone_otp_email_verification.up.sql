-- Section 4.1: the real registration flow — Page 1 (KYC + phone OTP) then
-- Page 2 (username/email/password) once the phone is verified. Neither SMS
-- nor email delivery exists yet (no provider selected — Section 9), so
-- these tables back a fully real generate/verify/rate-limit state machine
-- whose delivery leg is stubbed dev-visible only (see handlers/otp.go and
-- CreateMerchant) — not a fake flow, just one with no real courier yet.

CREATE TABLE phone_otps (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone         text NOT NULL,
  code          text NOT NULL,
  attempt_count int NOT NULL DEFAULT 0,
  verified_at   timestamptz,
  expires_at    timestamptz NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX phone_otps_phone_created_at_idx ON phone_otps(phone, created_at DESC);

CREATE TABLE email_verifications (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  token       text NOT NULL UNIQUE,
  expires_at  timestamptz NOT NULL,
  used_at     timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX email_verifications_merchant_id_idx ON email_verifications(merchant_id);

ALTER TABLE merchants ADD COLUMN username text UNIQUE;
ALTER TABLE merchants ADD COLUMN email_verified_at timestamptz;
