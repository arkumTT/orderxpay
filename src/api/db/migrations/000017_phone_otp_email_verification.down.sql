ALTER TABLE merchants DROP COLUMN email_verified_at;
ALTER TABLE merchants DROP COLUMN username;
DROP TABLE IF EXISTS email_verifications;
DROP TABLE IF EXISTS phone_otps;
