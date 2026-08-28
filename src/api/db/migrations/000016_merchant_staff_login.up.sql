-- Section 4.1/4.9: real email+password login for merchant owners and staff,
-- replacing the OTP-stub bypass for new registrations (OTP delivery itself
-- still isn't built — no SMS provider selected — but that no longer blocks
-- shipping login, since password auth doesn't need SMS at all).
--
-- Nullable: existing merchants/staff created before this migration simply
-- have no login credentials yet. They keep working via the dev-token
-- bypass in non-production, and would need credentials set through the app
-- once this ships for real users — there's no backfill possible since we
-- never had a plaintext password to hash for them.
ALTER TABLE merchants ADD COLUMN email text UNIQUE;
ALTER TABLE merchants ADD COLUMN password_hash text;

ALTER TABLE staff ADD COLUMN email text UNIQUE;
ALTER TABLE staff ADD COLUMN password_hash text;
