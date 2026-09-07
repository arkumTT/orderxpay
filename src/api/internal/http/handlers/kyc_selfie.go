package handlers

import (
	"errors"
	"io"
	"net/http"
	"os"
	"path/filepath"

	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// UploadKYCSelfie stores the liveness-check selfie captured on the merchant
// app (Section 4.1/7.1) — the final frame of an active blink + head-turn
// challenge run on-device with Google ML Kit face detection, not a plain
// gallery pick (the app never offers one for this field). This is an
// honest, not a commercial-grade, anti-spoofing measure: it stops someone
// holding up a static printed/screen photo, but a sufficiently produced
// pre-recorded video replay could still pass — the same caveat given to the
// merchant when this shipped.
//
// Deliberately mirrors UploadItemPhoto's validation (sniff real bytes via
// http.DetectContentType, cap size, uuid+ext filename) but diverges on
// storage and response: files land under KYCUploadDir (never app.Static-
// mounted — see KYCUploadDir's doc comment) and the response returns only
// the bare filename, never a URL, since nothing should construct a public
// link to it. The caller attaches that filename to a submission via the
// selfie_photo_path field on POST .../kyc-submissions.
func (h *Handler) UploadKYCSelfie(c *fiber.Ctx) error {
	merchantIDStr := c.Params("id")
	merchantID, err := parseUUID(merchantIDStr)
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	fileHeader, err := c.FormFile("selfie")
	if err != nil {
		return badRequest(c, "selfie file is required (multipart field \"selfie\")")
	}
	if fileHeader.Size > maxUploadBytes {
		return badRequest(c, "selfie must be under 3MB")
	}

	if _, err := h.Queries.GetMerchant(c.Context(), merchantID); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return notFound(c)
		}
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load merchant"})
	}

	file, err := fileHeader.Open()
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to read upload"})
	}
	defer file.Close()

	head := make([]byte, 512)
	n, err := file.Read(head)
	if err != nil && err != io.EOF {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to read upload"})
	}
	contentType := http.DetectContentType(head[:n])
	ext, ok := allowedImageContentTypes[contentType]
	if !ok {
		return badRequest(c, "only JPEG, PNG, or WebP images are allowed")
	}
	if _, err := file.Seek(0, io.SeekStart); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to read upload"})
	}

	dir := filepath.Join(h.KYCUploadDir, merchantIDStr)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to store upload"})
	}
	filename := uuid.NewString() + ext
	dest, err := os.Create(filepath.Join(dir, filename))
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to store upload"})
	}
	defer dest.Close()
	if _, err := io.Copy(dest, file); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to store upload"})
	}

	return c.JSON(fiber.Map{"selfie_photo_path": filename})
}

// GetKYCSelfiePhoto streams a submitted liveness-check selfie back to a
// Back Office reviewer (Section 7.1). Gated by merchants.kyc_review — the
// same permission that gates the review queue and the approve/reject
// action — never exposed through app.Static or any other unauthenticated
// path, since this is someone's face tied to a real identity document.
func (h *Handler) GetKYCSelfiePhoto(c *fiber.Ctx) error {
	id, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid submission id")
	}

	submission, err := h.Queries.GetKYCSubmission(c.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load submission"})
	}
	if !submission.SelfiePhotoPath.Valid || submission.SelfiePhotoPath.String == "" {
		return notFound(c)
	}

	merchantIDStr := uuid.UUID(submission.MerchantID.Bytes).String()
	path := filepath.Join(h.KYCUploadDir, merchantIDStr, submission.SelfiePhotoPath.String)
	if err := c.SendFile(path, false); err != nil {
		return notFound(c)
	}
	return nil
}
