package handlers

import (
	"encoding/json"
	"errors"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

type featureFlagWithMerchants struct {
	db.FeatureFlag
	Merchants []db.ListFeatureFlagMerchantsRow `json:"merchants"`
}

// ListFeatureFlags includes each flag's opted-in merchants inline (flag
// count is small — a handful of modules, not hundreds — so this N+1 is
// simpler than a join that would need to aggregate merchants into an
// array).
func (h *Handler) ListFeatureFlags(c *fiber.Ctx) error {
	flags, err := h.Queries.ListFeatureFlags(c.Context())
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list feature flags"})
	}

	result := make([]featureFlagWithMerchants, len(flags))
	for i, f := range flags {
		merchants, err := h.Queries.ListFeatureFlagMerchants(c.Context(), f.ID)
		if err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load flag merchants"})
		}
		result[i] = featureFlagWithMerchants{FeatureFlag: f, Merchants: merchants}
	}
	return c.JSON(result)
}

type setFeatureFlagGlobalRequest struct {
	EnabledGlobally bool `json:"enabled_globally"`
}

// SetFeatureFlagGlobal is the "flip it on for everyone" end state of a
// rollout (Section 7.4) — the per-merchant opt-in list below is how a
// subset gets it first.
func (h *Handler) SetFeatureFlagGlobal(c *fiber.Ctx) error {
	id, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid feature flag id")
	}
	var req setFeatureFlagGlobalRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}

	flag, err := h.Queries.GetFeatureFlag(c.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load feature flag"})
	}

	updated, err := h.Queries.SetFeatureFlagGlobal(c.Context(), db.SetFeatureFlagGlobalParams{
		ID:              id,
		EnabledGlobally: req.EnabledGlobally,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to update feature flag"})
	}

	before, _ := json.Marshal(fiber.Map{"enabled_globally": flag.EnabledGlobally})
	after, _ := json.Marshal(fiber.Map{"enabled_globally": updated.EnabledGlobally})
	if err := writeAdminAuditLog(c, h, "feature_flag.global_toggle", "feature_flag", id, before, after); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to write audit log"})
	}

	return c.JSON(updated)
}

type featureFlagMerchantRequest struct {
	MerchantID string `json:"merchant_id"`
}

func (h *Handler) AddFeatureFlagMerchant(c *fiber.Ctx) error {
	id, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid feature flag id")
	}
	var req featureFlagMerchantRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	merchantID, err := parseUUID(req.MerchantID)
	if err != nil {
		return badRequest(c, "invalid merchant_id")
	}

	if err := h.Queries.AddFeatureFlagMerchant(c.Context(), db.AddFeatureFlagMerchantParams{
		FeatureFlagID: id,
		MerchantID:    merchantID,
	}); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to add merchant to feature flag"})
	}

	after, _ := json.Marshal(fiber.Map{"merchant_id": req.MerchantID})
	if err := writeAdminAuditLog(c, h, "feature_flag.merchant_added", "feature_flag", id, nil, after); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to write audit log"})
	}

	return c.SendStatus(fiber.StatusNoContent)
}

func (h *Handler) RemoveFeatureFlagMerchant(c *fiber.Ctx) error {
	id, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid feature flag id")
	}
	merchantID, err := parseUUIDParam(c, "merchantId")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	if err := h.Queries.RemoveFeatureFlagMerchant(c.Context(), db.RemoveFeatureFlagMerchantParams{
		FeatureFlagID: id,
		MerchantID:    merchantID,
	}); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to remove merchant from feature flag"})
	}

	before, _ := json.Marshal(fiber.Map{"merchant_id": merchantID})
	if err := writeAdminAuditLog(c, h, "feature_flag.merchant_removed", "feature_flag", id, before, nil); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to write audit log"})
	}

	return c.SendStatus(fiber.StatusNoContent)
}
