package handlers

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"math/big"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

// lineItemRequest is one line of a CreateInvoice / order-request-confirm
// body. Either ItemID (a catalog item, Section 4.2) or
// Description+UnitPricePesewas (a one-off "quick-add" custom line) must be
// set.
type lineItemRequest struct {
	ItemID           string `json:"item_id"`
	Description      string `json:"description"`
	UnitPricePesewas int64  `json:"unit_price_pesewas"`
	Quantity         int32  `json:"quantity"`
}

type resolvedLineItem struct {
	ItemID           pgtype.UUID
	Description      string
	UnitPricePesewas int64
	Quantity         int32
	LineTotalPesewas int64
}

// validationError marks an error as the caller's fault (400), as opposed to
// an internal failure (500) — resolveLineItems/commissionForMerchant return
// a mix of both, so handlers need to tell them apart.
type validationError struct{ msg string }

func (e *validationError) Error() string { return e.msg }

func newValidationError(format string, args ...any) error {
	return &validationError{msg: fmt.Sprintf(format, args...)}
}

func isValidationError(err error) bool {
	var verr *validationError
	return errors.As(err, &verr)
}

var errInvalidLineItem = newValidationError("each line item needs a positive quantity and either item_id or description+unit_price_pesewas")

// resolveLineItems validates and prices each requested line: catalog items
// are looked up and price-snapshotted from the merchant's own catalog
// (Section 4.2) — a later price change never retroactively changes an
// issued invoice; custom items use the caller-supplied description/price
// directly.
func (h *Handler) resolveLineItems(ctx context.Context, merchantID pgtype.UUID, reqs []lineItemRequest) ([]resolvedLineItem, int64, error) {
	if len(reqs) == 0 {
		return nil, 0, newValidationError("at least one line item is required")
	}

	resolved := make([]resolvedLineItem, 0, len(reqs))
	var subtotal int64

	for _, req := range reqs {
		if req.Quantity <= 0 {
			return nil, 0, errInvalidLineItem
		}

		var line resolvedLineItem
		switch {
		case req.ItemID != "":
			itemID, err := parseUUID(req.ItemID)
			if err != nil {
				return nil, 0, newValidationError("invalid item_id %q", req.ItemID)
			}
			item, err := h.Queries.GetItem(ctx, itemID)
			if errors.Is(err, pgx.ErrNoRows) {
				return nil, 0, newValidationError("item %s not found", req.ItemID)
			} else if err != nil {
				return nil, 0, err
			}
			if item.MerchantID != merchantID {
				return nil, 0, newValidationError("item %s does not belong to this merchant", req.ItemID)
			}
			if item.ArchivedAt.Valid {
				return nil, 0, newValidationError("item %s is archived", req.ItemID)
			}
			line = resolvedLineItem{
				ItemID:           item.ID,
				Description:      item.Name,
				UnitPricePesewas: item.UnitPricePesewas,
				Quantity:         req.Quantity,
			}
		case req.Description != "" && req.UnitPricePesewas >= 0:
			line = resolvedLineItem{
				Description:      req.Description,
				UnitPricePesewas: req.UnitPricePesewas,
				Quantity:         req.Quantity,
			}
		default:
			return nil, 0, errInvalidLineItem
		}

		line.LineTotalPesewas = line.UnitPricePesewas * int64(line.Quantity)
		subtotal += line.LineTotalPesewas
		resolved = append(resolved, line)
	}

	return resolved, subtotal, nil
}

// invoiceAmounts is the Section 4.8 fee calculation. ServiceChargePesewas is
// always the amount disclosed to and paid by the customer on top of the
// subtotal: under merchant_only it's zero (the merchant absorbs the full
// commission at settlement instead); under split,
// merchants.service_charge_split_bps is the percentage of the commission
// charged to the customer, the remainder absorbed by the merchant.
type invoiceAmounts struct {
	CommissionPesewas    int64
	ServiceChargePesewas int64
	TotalPesewas         int64
}

func computeInvoiceAmounts(subtotal int64, commissionBps int32, allocation string, splitBps pgtype.Int4, deliveryFeePesewas int64, deliveryBundled bool) invoiceAmounts {
	commission := subtotal * int64(commissionBps) / 10000

	var serviceCharge int64
	switch allocation {
	case "customer_only":
		serviceCharge = commission
	case "merchant_only":
		serviceCharge = 0
	case "split":
		var bps int64
		if splitBps.Valid {
			bps = int64(splitBps.Int32)
		}
		serviceCharge = commission * bps / 10000
	}

	total := subtotal + serviceCharge
	if deliveryBundled {
		total += deliveryFeePesewas
	}

	return invoiceAmounts{
		CommissionPesewas:    commission,
		ServiceChargePesewas: serviceCharge,
		TotalPesewas:         total,
	}
}

// commissionForMerchant resolves the applicable commission rate: a
// merchant-specific override if one exists, else the platform default
// (Section 7.4).
func (h *Handler) commissionForMerchant(ctx context.Context, merchantID pgtype.UUID) (int32, error) {
	rule, err := h.Queries.GetFeeRuleByMerchant(ctx, merchantID)
	if errors.Is(err, pgx.ErrNoRows) {
		rule, err = h.Queries.GetGlobalFeeRule(ctx)
		if errors.Is(err, pgx.ErrNoRows) {
			return 0, errors.New("no fee rule configured — set a global default via POST /api/v1/admin/fee-rules/global")
		}
	}
	if err != nil {
		return 0, err
	}
	return rule.CommissionBps, nil
}

// invoiceReferenceAlphabet excludes 0/O and 1/I to avoid ambiguity when a
// customer reads or types the reference from a link/SMS.
const invoiceReferenceAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

func generateInvoiceReference() (string, error) {
	b := make([]byte, 10)
	for i := range b {
		n, err := rand.Int(rand.Reader, big.NewInt(int64(len(invoiceReferenceAlphabet))))
		if err != nil {
			return "", err
		}
		b[i] = invoiceReferenceAlphabet[n.Int64()]
	}
	return "INV-" + string(b), nil
}

func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}

type createInvoiceCoreParams struct {
	MerchantID          pgtype.UUID
	OrderRequestID      pgtype.UUID // zero value (Valid: false) if not created from an order request
	CustomerContact     string
	LineItems           []lineItemRequest
	DeliveryOptionID    pgtype.UUID
	DeliveryAddress     string
	DeliveryFeeHandling string // "bundled" | "external" | ""
	DeliveryFeePesewas  int64
}

const maxReferenceAttempts = 3

// createInvoiceCore is the shared engine behind both CreateInvoice and
// confirming an order request (Section 4.6) into a payable invoice.
func (h *Handler) createInvoiceCore(ctx context.Context, p createInvoiceCoreParams) (db.Invoice, []db.InvoiceLineItem, error) {
	merchant, err := h.Queries.GetMerchant(ctx, p.MerchantID)
	if err != nil {
		return db.Invoice{}, nil, fmt.Errorf("load merchant: %w", err)
	}

	resolvedLines, subtotal, err := h.resolveLineItems(ctx, p.MerchantID, p.LineItems)
	if err != nil {
		return db.Invoice{}, nil, err
	}

	commissionBps, err := h.commissionForMerchant(ctx, p.MerchantID)
	if err != nil {
		return db.Invoice{}, nil, err
	}

	deliveryBundled := p.DeliveryFeeHandling == "bundled"
	amounts := computeInvoiceAmounts(subtotal, commissionBps, merchant.ServiceChargeAllocation, merchant.ServiceChargeSplitBps, p.DeliveryFeePesewas, deliveryBundled)

	var lastErr error
	for attempt := 0; attempt < maxReferenceAttempts; attempt++ {
		invoice, lineItems, err := h.insertInvoice(ctx, p, resolvedLines, subtotal, merchant.ServiceChargeAllocation, amounts)
		if err == nil {
			return invoice, lineItems, nil
		}
		if !isUniqueViolation(err) {
			return db.Invoice{}, nil, err
		}
		lastErr = err // reference collision — astronomically unlikely, but retry with a fresh one rather than fail the sale
	}
	return db.Invoice{}, nil, fmt.Errorf("failed to generate a unique invoice reference after %d attempts: %w", maxReferenceAttempts, lastErr)
}

func (h *Handler) insertInvoice(ctx context.Context, p createInvoiceCoreParams, resolvedLines []resolvedLineItem, subtotal int64, allocation string, amounts invoiceAmounts) (db.Invoice, []db.InvoiceLineItem, error) {
	reference, err := generateInvoiceReference()
	if err != nil {
		return db.Invoice{}, nil, err
	}

	tx, err := h.Pool.Begin(ctx)
	if err != nil {
		return db.Invoice{}, nil, err
	}
	defer tx.Rollback(ctx)
	qtx := h.Queries.WithTx(tx)

	// A delivery fee can be set whenever delivery is configured for this
	// invoice at all (Section 4.11) — it isn't conditional on a saved
	// DeliveryOption being selected (an ad-hoc fee is valid too).
	var deliveryFeePesewas pgtype.Int8
	if p.DeliveryFeeHandling != "" {
		deliveryFeePesewas = pgtype.Int8{Int64: p.DeliveryFeePesewas, Valid: true}
	}

	invoice, err := qtx.CreateInvoice(ctx, db.CreateInvoiceParams{
		MerchantID:              p.MerchantID,
		OrderRequestID:          p.OrderRequestID,
		Reference:               reference,
		CustomerContact:         p.CustomerContact,
		SubtotalPesewas:         subtotal,
		ServiceChargePesewas:    amounts.ServiceChargePesewas,
		ServiceChargeAllocation: allocation,
		TotalPesewas:            amounts.TotalPesewas,
		DeliveryOptionID:        p.DeliveryOptionID,
		DeliveryAddress:         textOrNull(p.DeliveryAddress),
		DeliveryFeeHandling:     textOrNull(p.DeliveryFeeHandling),
		DeliveryFeePesewas:      deliveryFeePesewas,
		CommissionPesewas:       amounts.CommissionPesewas,
	})
	if err != nil {
		return db.Invoice{}, nil, fmt.Errorf("create invoice: %w", err)
	}

	lineItems := make([]db.InvoiceLineItem, 0, len(resolvedLines))
	for _, rl := range resolvedLines {
		li, err := qtx.CreateInvoiceLineItem(ctx, db.CreateInvoiceLineItemParams{
			InvoiceID:        invoice.ID,
			ItemID:           rl.ItemID,
			Description:      rl.Description,
			UnitPricePesewas: rl.UnitPricePesewas,
			Quantity:         rl.Quantity,
			LineTotalPesewas: rl.LineTotalPesewas,
		})
		if err != nil {
			return db.Invoice{}, nil, fmt.Errorf("create line item: %w", err)
		}
		lineItems = append(lineItems, li)
	}

	// Create and send are one action from the merchant app today: there's
	// no separate "send" step yet since Messaging (Section 4.4) is still a
	// stub, so we skip past Draft rather than leave the invoice stranded
	// there with no way to advance it.
	invoice, err = qtx.SetInvoiceStatus(ctx, db.SetInvoiceStatusParams{ID: invoice.ID, Status: "sent"})
	if err != nil {
		return db.Invoice{}, nil, fmt.Errorf("mark invoice sent: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return db.Invoice{}, nil, err
	}

	return invoice, lineItems, nil
}
