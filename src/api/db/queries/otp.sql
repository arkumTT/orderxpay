-- name: CountRecentPhoneOTPs :one
-- Rate-limit for RequestPhoneOTP: how many codes have been requested for
-- this phone since [since] (e.g. the last hour).
SELECT COUNT(*) FROM phone_otps WHERE phone = $1 AND created_at > $2;

-- name: CreatePhoneOTP :one
INSERT INTO phone_otps (phone, code, expires_at)
VALUES ($1, $2, $3)
RETURNING *;

-- name: GetLatestPhoneOTP :one
SELECT * FROM phone_otps WHERE phone = $1 ORDER BY created_at DESC LIMIT 1;

-- name: IncrementPhoneOTPAttempts :exec
UPDATE phone_otps SET attempt_count = attempt_count + 1 WHERE id = $1;

-- name: MarkPhoneOTPVerified :exec
UPDATE phone_otps SET verified_at = now() WHERE id = $1;

-- name: GetRecentVerifiedPhoneOTP :one
-- CreateMerchant checks this to confirm the phone was actually OTP-verified
-- (within [since], e.g. the last 30 minutes) before letting registration
-- through Page 2 proceed.
SELECT * FROM phone_otps
WHERE phone = $1 AND verified_at IS NOT NULL AND verified_at > $2
ORDER BY verified_at DESC LIMIT 1;
