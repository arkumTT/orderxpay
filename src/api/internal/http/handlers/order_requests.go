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

// orderRequestJSON re-presents db.OrderRequest.RequestedItems as actual JSON
// rather than the base64 string encoding/json produces for a bare []byte —
// the explicit field here shadows the promoted one from the embedded struct.
type orderRequestJSON struct {
	db.OrderRequest
	RequestedItems json.RawMessage `json:"requested_items"`
}

func toOrderRequestJSON(or db.OrderRequest) orderRequestJSON {
	return orderRequestJSON{OrderRequest: or, RequestedItems: json.RawMessage(or.RequestedItems)}
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
	return c.Status(fiber.StatusCreated).JSON(toOrderRequestJSON(orderRequest))
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
	result := make([]orderRequestJSON, len(requests))
	for i, r := range requests {
		result[i] = toOrderRequestJSON(r)
	}
	return c.JSON(result)
}

type setOrderRequestStatusRequest struct {
	Status        string `json:"status"` // confirmed | declined
	DeclineReason string `json:"decline_reason"`

	// Confirm-only: the merchant's final line items, which may differ from
	// what the customer originally requested — Section 4.6 lets the
	// merchant "confirm as-is, adjust quantities/items, or decline".
	LineItems           []lineItemRequest `json:"line_items"`
	DeliveryOptionID    string            `json:"delivery_option_id"`
	DeliveryAddress     string            `json:"delivery_address"`
	DeliveryFeeHandling string            `json:"delivery_fee_handling"`
	DeliveryFeePesewas  int64             `json:"delivery_fee_pesewas"`
}

// SetOrderRequestStatus lets the merchant confirm or decline a request
// (Section 4.6). Confirming auto-generates the payable invoice from the
// merchant's (possibly adjusted) line items via the same engine CreateInvoice
// uses, rather than blindly replaying the customer's original request.
func (h *Handler) SetOrderRequestStatus(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}
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

	orderRequest, err := h.Queries.GetOrderRequest(c.Context(), requestID)
	if errors.Is(err, pgx.ErrNoRows) {
		return notFound(c)
	} else if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load order request"})
	}
	if orderRequest.MerchantID != merchantID {
		return notFound(c)
	}
	if orderRequest.Status != "pending" {
		return badRequest(c, "order request has already been "+orderRequest.Status)
	}

	var invoice db.Invoice
	var lineItems []db.InvoiceLineItem
	if req.Status == "confirmed" {
		if len(req.LineItems) == 0 {
			return badRequest(c, "line_items is required to confirm an order request")
		}
		deliveryOptionID, err := uuidOrNull(req.DeliveryOptionID)
		if err != nil {
			return badRequest(c, "invalid delivery_option_id")
		}
		if req.DeliveryFeeHandling != "" && req.DeliveryFeeHandling != "bundled" && req.DeliveryFeeHandling != "external" {
			return badRequest(c, "delivery_fee_handling must be bundled or external")
		}

		invoice, lineItems, err = h.createInvoiceCore(c.Context(), createInvoiceCoreParams{
			MerchantID:          merchantID,
			OrderRequestID:      requestID,
			CustomerContact:     orderRequest.CustomerContact,
			LineItems:           req.LineItems,
			DeliveryOptionID:    deliveryOptionID,
			DeliveryAddress:     req.DeliveryAddress,
			DeliveryFeeHandling: req.DeliveryFeeHandling,
			DeliveryFeePesewas:  req.DeliveryFeePesewas,
		})
		if err != nil {
			if isValidationError(err) {
				return badRequest(c, err.Error())
			}
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to create invoice"})
		}
	}

	orderRequest, err = h.Queries.SetOrderRequestStatus(c.Context(), db.SetOrderRequestStatusParams{
		ID:            requestID,
		Status:        req.Status,
		DeclineReason: textOrNull(req.DeclineReason),
	})
	if err != nil {
		// The invoice (if any) was already committed above — status update
		// failing here leaves the request "pending" with an invoice that
		// already exists against it. Rare, and recoverable by retrying the
		// confirm call, but worth a TODO to fold into one transaction.
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to update order request status"})
	}

	if req.Status == "confirmed" {
		return c.JSON(fiber.Map{"order_request": toOrderRequestJSON(orderRequest), "invoice": invoice, "line_items": lineItems})
	}
	return c.JSON(toOrderRequestJSON(orderRequest))
}
