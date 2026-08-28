-- name: CreateEmailVerification :one
INSERT INTO email_verifications (merchant_id, token, expires_at)
VALUES ($1, $2, $3)
RETURNING *;

-- name: GetEmailVerificationByToken :one
SELECT * FROM email_verifications WHERE token = $1;

-- name: MarkEmailVerificationUsed :exec
UPDATE email_verifications SET used_at = now() WHERE id = $1;

-- name: MarkMerchantEmailVerified :one
UPDATE merchants SET email_verified_at = now() WHERE id = $1
RETURNING *;
