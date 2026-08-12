package handlers

import (
	"encoding/json"
	"errors"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

type createOrderRequestRequest struct {
	CustomerContact string          `json:"customer_contact"`
	RequestedItems  json.RawMessage `json:"requested_items"`
}

// CreateOrderRequest is the customer-initiated flow (Section 4.6, 12.2) —
// submitted from the hosted catalog page, so it is intentionally unauthenticated
// (no customer account exists). It creates a request, not a payable invoice.
func (h *Handler) CreateOrderRequest(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	var req createOrderRequestRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if req.CustomerContact == "" || len(req.RequestedItems) == 0 {
		return badRequest(c, "customer_contact and requested_items are required")
	}

	orderRequest, err := h.Queries.CreateOrderRequest(c.Context(), db.CreateOrderRequestParams{
		MerchantID:      merchantID,
		CustomerContact: req.CustomerContact,
		RequestedItems:  req.RequestedItems,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to create order request"})
	}
	return c.Status(fiber.StatusCreated).JSON(orderRequest)
}

// ListPendingOrderRequests backs the merchant's pending-request queue (Section 4.6).
func (h *Handler) ListPendingOrderRequests(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	requests, err := h.Queries.ListPendingOrderRequestsByMerchant(c.Context(), merchantID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to list order requests"})
	}
	return c.JSON(requests)
}

type setOrderRequestStatusRequest struct {
	Status        string `json:"status"` // confirmed | declined
	DeclineReason string `json:"decline_reason"`
}

// SetOrderRequestStatus lets the merchant confirm or decline a request
// (Section 4.6). TODO: on confirm, auto-generate the payable invoice from
// this request — depends on the invoice engine (see invoices.go).
func (h *Handler) SetOrderRequestStatus(c *fiber.Ctx) error {
	requestID, err := parseUUIDParam(c, "requestId")
	if err != nil {
		return badRequest(c, "invalid order request id")
	}

	var req setOrderRequestStatusRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	if req.Status != "confirmed" && req.Status != "declined" {
		return badRequest(c, "status must be confirmed or declined")
	}
	if req.Status == "declined" && req.DeclineReason == "" {
		return badRequest(c, "decline_reason is required when declining")
	}

	orderRequest, err := h.Queries.SetOrderRequestStatus(c.Context(), db.SetOrderRequestStatusParams{
		ID:            requestID,
		Status:        req.Status,
		DeclineReason: textOrNull(req.DeclineReason),
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to update order request"})
	}
	return c.JSON(orderRequest)
}
