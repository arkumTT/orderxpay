-- name: CreateKYCSubmission :one
INSERT INTO kyc_submissions (merchant_id, requested_tier, ghana_card_number, business_reg_number, notes)
VALUES ($1, $2, $3, $4, $5)
RETURNING *;

-- name: GetKYCSubmission :one
SELECT * FROM kyc_submissions WHERE id = $1;

-- name: GetOpenKYCSubmissionByMerchant :one
SELECT * FROM kyc_submissions
WHERE merchant_id = $1 AND status IN ('pending', 'more_info_requested')
LIMIT 1;

-- name: ResubmitKYCSubmission :one
-- Reuses the existing row after a more_info_requested response instead of
-- inserting a second one — kyc_submissions_one_open_per_merchant would
-- reject a second open row anyway, and this is the correct UX: the
-- reviewer's original notes/decision get replaced by the fresh review cycle.
UPDATE kyc_submissions
SET ghana_card_number = $2, business_reg_number = $3, notes = $4,
    status = 'pending', reviewer_notes = NULL, reviewed_by = NULL, reviewed_at = NULL
WHERE id = $1
RETURNING *;

-- name: ListKYCSubmissionsByMerchant :many
SELECT * FROM kyc_submissions WHERE merchant_id = $1 ORDER BY created_at DESC;

-- name: ListKYCSubmissionsAdmin :many
SELECT s.*, m.business_name AS merchant_business_name
FROM kyc_submissions s
JOIN merchants m ON m.id = s.merchant_id
WHERE (sqlc.arg(status_filter)::text = '' OR s.status = sqlc.arg(status_filter)::text)
ORDER BY s.created_at ASC
LIMIT sqlc.arg(row_limit) OFFSET sqlc.arg(row_offset);

-- name: ReviewKYCSubmission :one
UPDATE kyc_submissions
SET status = sqlc.arg(status), reviewer_notes = sqlc.arg(reviewer_notes),
    reviewed_by = sqlc.arg(reviewed_by), reviewed_at = now()
WHERE id = sqlc.arg(id)
RETURNING *;
