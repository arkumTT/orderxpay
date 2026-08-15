package handlers

import (
	"context"
	"encoding/json"
	"errors"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5"

	db "github.com/orderxpay/api/internal/db/sqlc"
	"github.com/orderxpay/api/internal/psp"
)

// paystackClient resolves the effective Paystack client for this call — a
// secret set through the Integrations page (Section 7.3) always wins over
// the env-configured one, and takes effect immediately on the next request,
// no restart required ("rotate keys ... without a code deployment"). Falls
// back to h.PSP (the startup-configured client) when no DB override is set,
// so existing behavior is unchanged until someone actually rotates the key.
func (h *Handler) paystackClient(ctx context.Context) *psp.Client {
	row, err := h.Queries.GetIntegration(ctx, "paystack")
	if err == nil && row.SecretValue.Valid && row.SecretValue.String != "" {
		return psp.NewClient(row.SecretValue.String)
	}
	return h.PSP
}

// integrationView strips secret_value entirely — ListIntegrations must
// never let the actual credential leave the server once it's been set
// (Section 7.3: "never displayed in plaintext after entry"). Hand-picking
// fields into a map, rather than tweaking the sqlc struct in place, means a
// future field added to the Integration model can't accidentally leak here.
func integrationView(r db.Integration) fiber.Map {
	return fiber.Map{
		"id":                r.ID,
		"provider_key":      r.ProviderKey,
		"category":          r.Category,
		"built":             r.Built,
		"has_secret":        r.SecretValue.Valid && r.SecretValue.String != "",
		"secret_updated_at": r.SecretUpdatedAt,
		"secret_updated_by": r.SecretUpdatedBy,
		"notes":             r.Notes,
		"created_at":        r.CreatedAt,
		"updated_at":        r.UpdatedAt,
	}
}

func (h *Handler) ListIntegrations(c *fiber.Ctx) error {
	rows, err := h.Queries.ListIntegrations(c.Context())
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list integrations"})
	}
	views := make([]fiber.Map, len(rows))
	for i, r := range rows {
		views[i] = integrationView(r)
	}
	return c.JSON(views)
}

type setIntegrationSecretRequest struct {
	SecretValue string `json:"secret_value"`
}

// SetIntegrationSecret only allows rotating a credential for an integration
// this codebase actually has working code for (built = true) — accepting a
// secret for whatsapp_bsp/sms_email/ussd_aggregator/gra_evat would store a
// value nothing ever reads, which is worse than not having the field.
func (h *Handler) SetIntegrationSecret(c *fiber.Ctx) error {
	providerKey := c.Params("key")

	existing, err := h.Queries.GetIntegration(c.Context(), providerKey)
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load integration"})
	}
	if !existing.Built {
		return badRequest(c, "this integration isn't built yet — no code reads this credential")
	}

	var req setIntegrationSecretRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if req.SecretValue == "" {
		return badRequest(c, "secret_value is required")
	}

	payload, ok := actorPayload(c)
	if !ok {
		return fiber.NewError(fiber.StatusUnauthorized, "missing auth payload")
	}

	updated, err := h.Queries.SetIntegrationSecret(c.Context(), db.SetIntegrationSecretParams{
		ProviderKey:     providerKey,
		SecretValue:     textOrNull(req.SecretValue),
		SecretUpdatedBy: toPgUUID(payload.ActorID),
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to update integration"})
	}

	// The audit trail records that a rotation happened, never the value
	// itself — same "never displayed in plaintext" spirit applies here.
	after, _ := json.Marshal(fiber.Map{"provider_key": providerKey, "action": "secret_rotated"})
	if err := writeAdminAuditLog(c, h, "integration.secret_rotated", "integration", updated.ID, nil, after); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to write audit log"})
	}

	return c.JSON(integrationView(updated))
}

type updateIntegrationNotesRequest struct {
	Notes string `json:"notes"`
}

func (h *Handler) UpdateIntegrationNotes(c *fiber.Ctx) error {
	providerKey := c.Params("key")

	var req updateIntegrationNotesRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}

	updated, err := h.Queries.UpdateIntegrationNotes(c.Context(), db.UpdateIntegrationNotesParams{
		ProviderKey: providerKey,
		Notes:       textOrNull(req.Notes),
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to update notes"})
	}

	after, _ := json.Marshal(fiber.Map{"notes": req.Notes})
	if err := writeAdminAuditLog(c, h, "integration.notes_updated", "integration", updated.ID, nil, after); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to write audit log"})
	}

	return c.JSON(integrationView(updated))
}

func (h *Handler) ListWebhookDeliveries(c *fiber.Ctx) error {
	limit := int32(c.QueryInt("limit", 50))
	offset := int32(c.QueryInt("offset", 0))

	deliveries, err := h.Queries.ListWebhookDeliveries(c.Context(), db.ListWebhookDeliveriesParams{
		Limit:  limit,
		Offset: offset,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list webhook deliveries"})
	}
	return c.JSON(deliveries)
}

func (h *Handler) ListDeliveryProviders(c *fiber.Ctx) error {
	providers, err := h.Queries.ListDeliveryProviders(c.Context())
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list delivery providers"})
	}
	return c.JSON(providers)
}

type deliveryProviderRequest struct {
	Key              string `json:"key"`
	Name             string `json:"name"`
	DeepLinkTemplate string `json:"deep_link_template"`
	Notes            string `json:"notes"`
}

func (h *Handler) CreateDeliveryProvider(c *fiber.Ctx) error {
	var req deliveryProviderRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if req.Key == "" || req.Name == "" || req.DeepLinkTemplate == "" {
		return badRequest(c, "key, name, and deep_link_template are required")
	}

	provider, err := h.Queries.CreateDeliveryProvider(c.Context(), db.CreateDeliveryProviderParams{
		Key:              req.Key,
		Name:             req.Name,
		DeepLinkTemplate: req.DeepLinkTemplate,
		Notes:            textOrNull(req.Notes),
	})
	if err != nil {
		return c.Status(fiber.StatusConflict).JSON(fiber.Map{"error": "a provider with this key may already exist"})
	}

	after, _ := json.Marshal(fiber.Map{"key": provider.Key, "name": provider.Name})
	if err := writeAdminAuditLog(c, h, "delivery_provider.create", "delivery_provider", provider.ID, nil, after); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to write audit log"})
	}

	return c.Status(fiber.StatusCreated).JSON(provider)
}

type updateDeliveryProviderRequest struct {
	Name             string `json:"name"`
	DeepLinkTemplate string `json:"deep_link_template"`
	Status           string `json:"status"`
	Notes            string `json:"notes"`
}

func (h *Handler) UpdateDeliveryProvider(c *fiber.Ctx) error {
	id, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid delivery provider id")
	}

	var req updateDeliveryProviderRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if req.Name == "" || req.DeepLinkTemplate == "" {
		return badRequest(c, "name and deep_link_template are required")
	}
	if req.Status != "active" && req.Status != "inactive" {
		return badRequest(c, "status must be active or inactive")
	}

	updated, err := h.Queries.UpdateDeliveryProvider(c.Context(), db.UpdateDeliveryProviderParams{
		ID:               id,
		Name:             req.Name,
		DeepLinkTemplate: req.DeepLinkTemplate,
		Status:           req.Status,
		Notes:            textOrNull(req.Notes),
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to update delivery provider"})
	}

	after, _ := json.Marshal(fiber.Map{"name": updated.Name, "status": updated.Status})
	if err := writeAdminAuditLog(c, h, "delivery_provider.update", "delivery_provider", id, nil, after); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to write audit log"})
	}

	return c.JSON(updated)
}

func (h *Handler) DeleteDeliveryProvider(c *fiber.Ctx) error {
	id, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid delivery provider id")
	}

	if err := h.Queries.DeleteDeliveryProvider(c.Context(), id); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to delete delivery provider"})
	}

	if err := writeAdminAuditLog(c, h, "delivery_provider.delete", "delivery_provider", id, nil, nil); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to write audit log"})
	}

	return c.SendStatus(fiber.StatusNoContent)
}
