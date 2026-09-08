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

// Shared plumbing for the two files a KYC submission can carry: the
// liveness-check selfie (kyc_selfie.go) and, on the registered fork, a
// business registration certificate.
//
// Both land under KYCUploadDir/{merchant_id}/ — deliberately outside the
// app.Static("/uploads", ...) mount used for catalog item photos — and are
// read back only through a handler gated by merchants.kyc_review. Neither
// is ever addressable by URL.
//
// Note what is NOT here and must not be added: any capture of the Ghana
// Card itself. The card is verified by number plus liveness check, because
// copying or scanning Ghana Card IDs is restricted. A registration
// certificate is an ordinary commercial document and carries no such
// restriction — that is the whole reason one of these has a file and the
// other does not.

// allowedCertContentTypes is deliberately wider than
// allowedImageContentTypes: a registration certificate arrives as a PDF at
// least as often as a photo of the paper document.
var allowedCertContentTypes = map[string]string{
	"image/jpeg":      ".jpg",
	"image/png":       ".png",
	"image/webp":      ".webp",
	"application/pdf": ".pdf",
}

// storeKYCUpload validates and writes one uploaded file into the merchant's
// private KYC directory, returning the bare filename to attach to a
// submission. Content type is sniffed from the file's actual first bytes
// via http.DetectContentType rather than trusted from the client-supplied
// header, which can be spoofed.
func (h *Handler) storeKYCUpload(c *fiber.Ctx, formField, typeErrMsg string, allowed map[string]string) (string, error) {
	merchantIDStr := c.Params("id")
	merchantID, err := parseUUID(merchantIDStr)
	if err != nil {
		return "", badRequest(c, "invalid merchant id")
	}

	fileHeader, err := c.FormFile(formField)
	if err != nil {
		return "", badRequest(c, formField+" file is required (multipart field \""+formField+"\")")
	}
	if fileHeader.Size > maxUploadBytes {
		return "", badRequest(c, formField+" must be under 3MB")
	}

	if _, err := h.Queries.GetMerchant(c.Context(), merchantID); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", notFound(c)
		}
		return "", c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load merchant"})
	}

	file, err := fileHeader.Open()
	if err != nil {
		return "", c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to read upload"})
	}
	defer file.Close()

	head := make([]byte, 512)
	n, err := file.Read(head)
	if err != nil && err != io.EOF {
		return "", c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to read upload"})
	}
	ext, ok := allowed[http.DetectContentType(head[:n])]
	if !ok {
		return "", badRequest(c, typeErrMsg)
	}
	if _, err := file.Seek(0, io.SeekStart); err != nil {
		return "", c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to read upload"})
	}

	dir := filepath.Join(h.KYCUploadDir, merchantIDStr)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to store upload"})
	}
	filename := uuid.NewString() + ext
	dest, err := os.Create(filepath.Join(dir, filename))
	if err != nil {
		return "", c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to store upload"})
	}
	defer dest.Close()
	if _, err := io.Copy(dest, file); err != nil {
		return "", c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to store upload"})
	}
	return filename, nil
}

// UploadKYCRegistrationCert stores the business registration certificate
// that the registered fork requires (Section 4.1). The merchant attaches
// the returned filename to a submission via registration_cert_path.
func (h *Handler) UploadKYCRegistrationCert(c *fiber.Ctx) error {
	filename, err := h.storeKYCUpload(c, "certificate",
		"the certificate must be a PDF, JPEG, PNG or WebP file",
		allowedCertContentTypes)
	if err != nil {
		return err
	}
	return c.JSON(fiber.Map{"registration_cert_path": filename})
}

// GetKYCRegistrationCert streams a submitted registration certificate back
// to a reviewer, gated by merchants.kyc_review exactly as the selfie is.
func (h *Handler) GetKYCRegistrationCert(c *fiber.Ctx) error {
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
	if !submission.RegistrationCertPath.Valid || submission.RegistrationCertPath.String == "" {
		return notFound(c)
	}

	merchantIDStr := uuid.UUID(submission.MerchantID.Bytes).String()
	path := filepath.Join(h.KYCUploadDir, merchantIDStr, submission.RegistrationCertPath.String)
	if err := c.SendFile(path, false); err != nil {
		return notFound(c)
	}
	return nil
}
