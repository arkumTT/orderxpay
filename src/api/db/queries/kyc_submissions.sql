-- name: CreateKYCSubmission :one
-- requested_tier is not caller-chosen: the schema pins informal to 1 and
-- registered to 2, so the tier always matches the evidence reviewed.
INSERT INTO kyc_submissions (
  merchant_id, business_type, requested_tier, ghana_card_number, selfie_photo_path,
  business_reg_number, tin, entity_type, registration_cert_path, notes
) VALUES (
  sqlc.arg(merchant_id), sqlc.arg(business_type),
  CASE WHEN sqlc.arg(business_type)::text = 'registered' THEN 2 ELSE 1 END,
  sqlc.arg(ghana_card_number), sqlc.arg(selfie_photo_path),
  sqlc.arg(business_reg_number), sqlc.arg(tin), sqlc.arg(entity_type),
  sqlc.arg(registration_cert_path), sqlc.arg(notes)
)
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
-- A resubmission may also switch fork — an informal trader who registers
-- their business between review cycles resubmits as 'registered', and
-- requested_tier moves with it.
UPDATE kyc_submissions
SET business_type = sqlc.arg(business_type),
    requested_tier = CASE WHEN sqlc.arg(business_type)::text = 'registered' THEN 2 ELSE 1 END,
    ghana_card_number = sqlc.arg(ghana_card_number),
    selfie_photo_path = sqlc.arg(selfie_photo_path),
    business_reg_number = sqlc.arg(business_reg_number),
    tin = sqlc.arg(tin),
    entity_type = sqlc.arg(entity_type),
    registration_cert_path = sqlc.arg(registration_cert_path),
    notes = sqlc.arg(notes),
    status = 'pending', reviewer_notes = NULL, reviewed_by = NULL, reviewed_at = NULL
WHERE id = sqlc.arg(id)
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
