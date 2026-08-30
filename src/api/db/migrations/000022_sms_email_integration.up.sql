-- Real SMS (Arkesel) and email (generic SMTP) delivery for registration
-- OTP and email verification (Section 9 — previously dev-stub-only, see
-- otp.go/merchants.go). Flips the Back Office Integrations page from
-- "Not built" to built for sms_email, which is also what unlocks
-- SetIntegrationSecret for it (the handler refuses to store a secret for
-- an integration nothing reads). The stored secret is the SMS API key
-- specifically — SMTP stays env-configured only, see email.Client's doc
-- comment for why.
UPDATE integrations SET built = true WHERE provider_key = 'sms_email';
