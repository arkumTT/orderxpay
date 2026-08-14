package handlers

import (
	"encoding/json"
	"errors"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

type submitKYCRequest struct {
	GhanaCardNumber   string `json:"ghana_card_number"`
	BusinessRegNumber string `json:"business_reg_number"`
	Notes             string `json:"notes"`
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
	if req.GhanaCardNumber == "" {
		return badRequest(c, "ghana_card_number is required")
	}

	merchant, err := h.Queries.GetMerchant(c.Context(), merchantID)
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load merchant"})
	}
	if merchant.KycTier >= 1 {
		return badRequest(c, "merchant is already Tier 1 verified")
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
			ID:                existing.ID,
			GhanaCardNumber:   req.GhanaCardNumber,
			BusinessRegNumber: textOrNull(req.BusinessRegNumber),
			Notes:             textOrNull(req.Notes),
		})
		if err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to resubmit KYC"})
		}
		return c.JSON(updated)
	}

	submission, err := h.Queries.CreateKYCSubmission(c.Context(), db.CreateKYCSubmissionParams{
		MerchantID:        merchantID,
		RequestedTier:     1,
		GhanaCardNumber:   req.GhanaCardNumber,
		BusinessRegNumber: textOrNull(req.BusinessRegNumber),
		Notes:             textOrNull(req.Notes),
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
		if _, err := qtx.UpdateMerchantKYCTier(c.Context(), db.UpdateMerchantKYCTierParams{
			ID:      submission.MerchantID,
			KycTier: submission.RequestedTier,
		}); err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to update merchant KYC tier"})
		}
	}

	before, _ := json.Marshal(fiber.Map{"status": submission.Status})
	after, _ := json.Marshal(fiber.Map{"status": updated.Status, "reviewer_notes": req.ReviewerNotes})
	if err := writeAdminAuditLog(c, h, "kyc.review", "kyc_submission", id, before, after); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to write audit log"})
	}

	if err := tx.Commit(c.Context()); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to commit review"})
	}

	return c.JSON(updated)
}
