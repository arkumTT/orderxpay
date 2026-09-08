package handlers

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

// entityTypes are the Ghanaian business forms a registered merchant can
// declare. Kept in lockstep with the kyc_submissions.entity_type CHECK — a
// value the schema rejects should never reach the database as a 500.
var entityTypes = map[string]bool{
	"sole_proprietorship":          true,
	"partnership":                  true,
	"company_limited_by_shares":    true,
	"company_limited_by_guarantee": true,
	"ngo":                          true,
}

type submitKYCRequest struct {
	// BusinessType forks the whole submission (Section 4.1):
	//
	//   informal    a trader with no registered entity — Ghana Card number
	//               plus liveness, and nothing more. Approves to Tier 1.
	//   registered  a registered business — the same identity evidence plus
	//               a TIN, registration number, entity type and a scan of
	//               the registration certificate. Approves to Tier 2.
	//
	// The requested tier is derived from this, never sent by the client:
	// the schema pins informal to 1 and registered to 2 so the tier a
	// merchant ends up with always matches the evidence a reviewer saw.
	BusinessType string `json:"business_type"`

	// Both forks. The Ghana Card is captured as a number plus a liveness
	// check and nothing else — no image of the card is requested, uploaded
	// or stored anywhere in this codebase, in line with the restriction on
	// copying and scanning Ghana Card IDs. Do not add one.
	GhanaCardNumber string `json:"ghana_card_number"`
	// SelfiePhotoPath is the bare filename returned by a prior call to
	// POST .../kyc-submissions/selfie (see UploadKYCSelfie) — the final
	// frame of the on-device liveness challenge, not a freely-chosen
	// gallery photo. Required on both forks: Section 4.1/7.1 makes the
	// liveness check a requisite part of verification, not an add-on.
	SelfiePhotoPath string `json:"selfie_photo_path"`

	// Registered fork only, all four required together. Unlike the Ghana
	// Card, a business registration certificate is an ordinary commercial
	// document, so RegistrationCertPath holds a real uploaded file (see
	// UploadKYCRegistrationCert) stored the same private, permission-gated
	// way the liveness selfie is.
	BusinessRegNumber    string `json:"business_reg_number"`
	Tin                  string `json:"tin"`
	EntityType           string `json:"entity_type"`
	RegistrationCertPath string `json:"registration_cert_path"`

	Notes string `json:"notes"`
}

// normalize trims every field and, on the informal fork, clears the
// registered-only evidence rather than storing it. An informal submission
// carrying a half-filled TIN would give a reviewer something to weigh that
// the fork says is not part of this decision.
func (r *submitKYCRequest) normalize() {
	r.BusinessType = strings.TrimSpace(r.BusinessType)
	r.GhanaCardNumber = strings.TrimSpace(r.GhanaCardNumber)
	r.SelfiePhotoPath = strings.TrimSpace(r.SelfiePhotoPath)
	r.BusinessRegNumber = strings.TrimSpace(r.BusinessRegNumber)
	r.Tin = strings.TrimSpace(r.Tin)
	r.EntityType = strings.TrimSpace(r.EntityType)
	r.RegistrationCertPath = strings.TrimSpace(r.RegistrationCertPath)
	r.Notes = strings.TrimSpace(r.Notes)

	if r.BusinessType == "informal" {
		r.Tin = ""
		r.EntityType = ""
		r.RegistrationCertPath = ""
	}
}

// validate mirrors the kyc_submissions_registered_evidence CHECK, so the
// merchant gets a sentence naming the missing field instead of a constraint
// violation surfacing as a 500.
func (r submitKYCRequest) validate() error {
	if r.BusinessType != "informal" && r.BusinessType != "registered" {
		return errors.New("business_type must be informal or registered")
	}
	if r.GhanaCardNumber == "" {
		return errors.New("ghana_card_number is required")
	}
	if r.SelfiePhotoPath == "" {
		return errors.New("selfie_photo_path is required — complete the liveness check first")
	}
	if r.BusinessType != "registered" {
		return nil
	}
	if r.BusinessRegNumber == "" {
		return errors.New("business_reg_number is required for a registered business")
	}
	if r.Tin == "" {
		return errors.New("tin is required for a registered business")
	}
	if !entityTypes[r.EntityType] {
		return errors.New("entity_type must be one of sole_proprietorship, partnership, company_limited_by_shares, company_limited_by_guarantee, ngo")
	}
	if r.RegistrationCertPath == "" {
		return errors.New("registration_cert_path is required — upload your registration certificate first")
	}
	return nil
}

// requestedTier is derived, never taken from the client.
func (r submitKYCRequest) requestedTier() int16 {
	if r.BusinessType == "registered" {
		return 2
	}
	return 1
}

// CreateKYCSubmission is the merchant-app entry point for a Tier 1 upgrade
// request (Section 4.1). If the merchant already has an open submission
// that was sent back for more info, this updates that row and puts it back
// in the queue rather than creating a second one — the
// kyc_submissions_one_open_per_merchant index enforces at most one open
// submission either way.
func (h *Handler) CreateKYCSubmission(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	var req submitKYCRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	req.normalize()
	if err := req.validate(); err != nil {
		return badRequest(c, err.Error())
	}

	merchant, err := h.Queries.GetMerchant(c.Context(), merchantID)
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load merchant"})
	}
	// Compared against the requested tier, not against 1: a Tier 1 informal
	// trader who later registers their business must be able to submit
	// again for Tier 2. Only a submission that would not move them forward
	// is refused.
	if merchant.KycTier >= req.requestedTier() {
		return badRequest(c, fmt.Sprintf("merchant is already Tier %d verified", merchant.KycTier))
	}

	existing, err := h.Queries.GetOpenKYCSubmissionByMerchant(c.Context(), merchantID)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to check existing submissions"})
	}

	if err == nil {
		// An open submission exists.
		if existing.Status == "pending" {
			return c.Status(fiber.StatusConflict).JSON(fiber.Map{"error": "a submission is already awaiting review"})
		}
		// status == "more_info_requested" — resubmit onto the same row.
		updated, err := h.Queries.ResubmitKYCSubmission(c.Context(), db.ResubmitKYCSubmissionParams{
			ID:                   existing.ID,
			BusinessType:         req.BusinessType,
			GhanaCardNumber:      req.GhanaCardNumber,
			SelfiePhotoPath:      textOrNull(req.SelfiePhotoPath),
			BusinessRegNumber:    textOrNull(req.BusinessRegNumber),
			Tin:                  textOrNull(req.Tin),
			EntityType:           textOrNull(req.EntityType),
			RegistrationCertPath: textOrNull(req.RegistrationCertPath),
			Notes:                textOrNull(req.Notes),
		})
		if err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to resubmit KYC"})
		}
		return c.JSON(updated)
	}

	submission, err := h.Queries.CreateKYCSubmission(c.Context(), db.CreateKYCSubmissionParams{
		MerchantID:           merchantID,
		BusinessType:         req.BusinessType,
		GhanaCardNumber:      req.GhanaCardNumber,
		SelfiePhotoPath:      textOrNull(req.SelfiePhotoPath),
		BusinessRegNumber:    textOrNull(req.BusinessRegNumber),
		Tin:                  textOrNull(req.Tin),
		EntityType:           textOrNull(req.EntityType),
		RegistrationCertPath: textOrNull(req.RegistrationCertPath),
		Notes:                textOrNull(req.Notes),
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to create KYC submission"})
	}
	return c.Status(fiber.StatusCreated).JSON(submission)
}

// ListKYCSubmissionsByMerchant lets the merchant app show submission status
// (Section 4.1's "Verify & Withdraw" screen).
func (h *Handler) ListKYCSubmissionsByMerchant(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}
	submissions, err := h.Queries.ListKYCSubmissionsByMerchant(c.Context(), merchantID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list KYC submissions"})
	}
	return c.JSON(submissions)
}

// ListKYCSubmissionsAdmin backs the Back Office KYC review queue (Section
// 7.1). The frontend splits open (pending/more_info_requested) from
// resolved (approved/rejected) client-side rather than this endpoint
// enforcing a single notion of "the queue".
func (h *Handler) ListKYCSubmissionsAdmin(c *fiber.Ctx) error {
	limit := int32(c.QueryInt("limit", 100))
	offset := int32(c.QueryInt("offset", 0))

	submissions, err := h.Queries.ListKYCSubmissionsAdmin(c.Context(), db.ListKYCSubmissionsAdminParams{
		StatusFilter: c.Query("status"),
		RowLimit:     limit,
		RowOffset:    offset,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list KYC submissions"})
	}
	return c.JSON(submissions)
}

// kycStatusTransitions mirrors settlementStatusTransitions' shape: pending
// and more_info_requested are open states a reviewer can move between or
// resolve from; approved/rejected are terminal.
var kycStatusTransitions = map[string][]string{
	"pending":             {"approved", "rejected", "more_info_requested"},
	"more_info_requested": {"approved", "rejected"},
}

type reviewKYCRequest struct {
	Status        string `json:"status"`
	ReviewerNotes string `json:"reviewer_notes"`
}

// ReviewKYCSubmission is the Back Office approve/reject/request-more-info
// action (Section 7.1). Approving also bumps the merchant's kyc_tier —
// atomically, so a submission can never end up "approved" while the
// merchant is still stuck at Tier 0. Always audited (Section 7.9 names "KYC
// approval/rejection" explicitly as a sensitive action to log).
func (h *Handler) ReviewKYCSubmission(c *fiber.Ctx) error {
	id, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid submission id")
	}

	var req reviewKYCRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if req.Status == "rejected" && req.ReviewerNotes == "" {
		return badRequest(c, "reviewer_notes is required when rejecting")
	}
	if req.Status == "more_info_requested" && req.ReviewerNotes == "" {
		return badRequest(c, "reviewer_notes is required to explain what's needed")
	}

	submission, err := h.Queries.GetKYCSubmission(c.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load submission"})
	}

	allowed := kycStatusTransitions[submission.Status]
	valid := false
	for _, s := range allowed {
		if s == req.Status {
			valid = true
			break
		}
	}
	if !valid {
		return badRequest(c, "cannot move submission from "+submission.Status+" to "+req.Status)
	}

	payload, ok := actorPayload(c)
	if !ok {
		return fiber.NewError(fiber.StatusUnauthorized, "missing auth payload")
	}

	tx, err := h.Pool.Begin(c.Context())
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to start transaction"})
	}
	defer tx.Rollback(c.Context())
	qtx := h.Queries.WithTx(tx)

	updated, err := qtx.ReviewKYCSubmission(c.Context(), db.ReviewKYCSubmissionParams{
		ID:            id,
		Status:        req.Status,
		ReviewerNotes: textOrNull(req.ReviewerNotes),
		ReviewedBy:    toPgUUID(payload.ActorID),
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to update submission"})
	}

	if req.Status == "approved" {
		// Tier and fork land together so a Tier 2 merchant always carries
		// business_type 'registered' — the two cannot drift apart.
		if _, err := qtx.ApproveMerchantKYC(c.Context(), db.ApproveMerchantKYCParams{
			ID:           submission.MerchantID,
			KycTier:      submission.RequestedTier,
			BusinessType: textOrNull(submission.BusinessType),
		}); err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to update merchant KYC tier"})
		}
	}

	before, _ := json.Marshal(fiber.Map{"status": submission.Status})
	after, _ := json.Marshal(fiber.Map{"status": updated.Status, "reviewer_notes": req.ReviewerNotes})
	if err := writeAdminAuditLog(c, h, "kyc.review", "kyc_submission", id, before, after); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to write audit log"})
	}

	// Atomic with the status change (Section 4.10) — unlike the payment/
	// order-request/settlement trigger points, this handler already runs
	// inside a transaction, so there's no reason to make this best-effort.
	body := "Your verification submission was rejected: " + req.ReviewerNotes
	switch updated.Status {
	case "approved":
		body = fmt.Sprintf("Your verification was approved — you're now Tier %d.", submission.RequestedTier)
	case "more_info_requested":
		body = "More information is needed for your verification: " + req.ReviewerNotes
	}
	if _, err := qtx.CreateNotification(c.Context(), db.CreateNotificationParams{
		MerchantID:   submission.MerchantID,
		Type:         "kyc_status_change",
		Title:        "Verification " + strings.ReplaceAll(updated.Status, "_", " "),
		Body:         body,
		TargetEntity: textOrNull("kyc_submission"),
		TargetID:     updated.ID,
	}); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to create notification"})
	}

	if err := tx.Commit(c.Context()); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to commit review"})
	}

	// Push (Section 4.10 Phase 2) deliberately happens after commit, not
	// inside the transaction above — a push-send failure must never roll
	// back a review decision that's otherwise already succeeded.
	h.pushToMerchant(c.Context(), submission.MerchantID, "Verification "+strings.ReplaceAll(updated.Status, "_", " "), body, map[string]string{
		"target_entity": "kyc_submission",
		"target_id":     uuid.UUID(updated.ID.Bytes).String(),
	})

	return c.JSON(updated)
}
