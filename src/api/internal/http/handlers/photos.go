package handlers

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"

	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

const (
	// merchantStorageQuotaBytes is deliberately modest: at a typical
	// compressed-on-device photo of ~150-300KB (see the mobile item form's
	// pick+compress step), 50MB is room for roughly 150-300 item photos —
	// far more than a small retailer's catalog needs, while keeping local
	// disk usage bounded per merchant (Section 4.2).
	merchantStorageQuotaBytes = 50 * 1024 * 1024 // 50MB
	// maxUploadBytes caps a single file well above what a compressed photo
	// should ever be, as a sanity backstop against an uncompressed upload
	// slipping through.
	maxUploadBytes = 3 * 1024 * 1024 // 3MB
)

// allowedImageContentTypes maps a sniffed MIME type (via http.DetectContentType
// on the file's actual bytes, not the client-supplied filename/header — that
// can be spoofed) to the extension saved to disk.
var allowedImageContentTypes = map[string]string{
	"image/jpeg": ".jpg",
	"image/png":  ".png",
	"image/webp": ".webp",
}

// UploadItemPhoto stores a catalog item photo on local disk (Section 4.2)
// — no cloud storage account exists, so this is deliberately the simplest
// thing that works: a merchant-scoped directory under UploadDir, served
// back publicly via app.Static("/uploads", ...) since item photos are
// meant to be visible to any customer (same posture as the hosted catalog
// page). Returns the resulting image_url for the caller to attach to an
// item via the existing CreateItem/UpdateItem image_url field — this
// endpoint only handles the file, not the item record itself.
func (h *Handler) UploadItemPhoto(c *fiber.Ctx) error {
	merchantIDStr := c.Params("id")
	merchantID, err := parseUUID(merchantIDStr)
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	fileHeader, err := c.FormFile("photo")
	if err != nil {
		return badRequest(c, "photo file is required (multipart field \"photo\")")
	}
	if fileHeader.Size > maxUploadBytes {
		return badRequest(c, "photo must be under 3MB — compress it before uploading")
	}

	merchant, err := h.Queries.GetMerchant(c.Context(), merchantID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load merchant"})
	}
	if merchant.StorageUsedBytes+fileHeader.Size > merchantStorageQuotaBytes {
		return c.Status(fiber.StatusRequestEntityTooLarge).JSON(fiber.Map{
			"error":               fmt.Sprintf("storage quota exceeded (%dMB) — remove some item photos first", merchantStorageQuotaBytes/1024/1024),
			"storage_used_bytes":  merchant.StorageUsedBytes,
			"storage_quota_bytes": merchantStorageQuotaBytes,
		})
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

	dir := filepath.Join(h.UploadDir, merchantIDStr)
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

	updated, err := h.Queries.IncrementMerchantStorageUsed(c.Context(), db.IncrementMerchantStorageUsedParams{
		ID:               merchantID,
		StorageUsedBytes: fileHeader.Size,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to update storage usage"})
	}

	imageURL := fmt.Sprintf("%s/uploads/%s/%s", h.APIPublicBaseURL, merchantIDStr, filename)
	return c.JSON(fiber.Map{
		"image_url":           imageURL,
		"storage_used_bytes":  updated.StorageUsedBytes,
		"storage_quota_bytes": merchantStorageQuotaBytes,
	})
}
