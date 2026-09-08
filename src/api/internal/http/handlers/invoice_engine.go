package handlers

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"log"
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
// an internal failure (500) — resolveLineItems/pricingForMerchant return
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

// pricing is a fee rule resolved down to what the invoice engine needs.
// Splitting the PSP pass-through from OrderxPay's own margin is what makes
// the clamps below safe: only the margin is ever floored or capped, so a
// capped invoice can still never cost more to process than it charges.
type pricing struct {
	CollectionFeeBps int32 // paid on to the PSP
	MarginBps        int32 // OrderxPay's take
	MarginFloor      int64 // pesewas; 0 = no floor
	MarginCap        int64 // pesewas; 0 = no cap
}

// commissionBps is the blended rate a merchant sees quoted.
func (p pricing) commissionBps() int32 { return p.CollectionFeeBps + p.MarginBps }

// invoiceAmounts is the Section 4.8 fee calculation.
//
// Three properties this has to hold:
//
//  1. The commission base is the full amount that actually moves through
//     the PSP — goods plus any delivery fee bundled into the invoice — not
//     the goods subtotal alone. The PSP charges its percentage on
//     everything it collects, so commissioning only the subtotal meant a
//     bundled delivery fee cost OrderxPay a fee it earned nothing back on:
//     a ₵20 order carrying a ₵50 delivery fee settled at a real loss.
//
//  2. The customer-borne share is grossed up, not added on top. Adding
//     2.5% to ₵100 bills ₵102.50 — but the PSP then takes its cut of
//     ₵102.50, so the realised margin lands under the configured rate.
//     Solving total = base / (1 - rate) bills ₵102.56 instead, and leaves
//     the merchant exactly their asking price.
//
//  3. The margin is clamped at both ends. A percentage of a ₵10 invoice is
//     not worth carrying; a percentage of a ₵50,000 invoice is visible
//     enough that the merchant takes the payment off-platform instead. The
//     floor and cap apply to OrderxPay's margin only — the PSP portion is
//     always passed through in full, so the platform's take can be squeezed
//     to the cap but never below its own cost.
//
// ServiceChargePesewas keeps its original meaning: the amount disclosed to
// and paid by the customer on top of the merchant's asking price — zero
// under merchant_only, the whole commission under customer_only, and
// merchants.service_charge_split_bps of it under split.
type invoiceAmounts struct {
	CommissionPesewas    int64
	ServiceChargePesewas int64
	TotalPesewas         int64
}

// customerCommissionShareBps is how much of the commission the customer pays
// on top of the merchant's asking price, in bps of the commission (10000 =
// the customer pays all of it). An unrecognised allocation is treated as
// merchant_only — the safe direction, since it never surprises a customer
// with an undisclosed charge.
func customerCommissionShareBps(allocation string, splitBps pgtype.Int4) int64 {
	switch allocation {
	case "customer_only":
		return 10000
	case "split":
		if !splitBps.Valid {
			return 0
		}
		share := int64(splitBps.Int32)
		if share < 0 {
			return 0
		}
		if share > 10000 {
			return 10000
		}
		return share
	default:
		return 0
	}
}

// grossUp solves total = amount / (1 - effectiveBps), rounding to the
// nearest pesewa so the merchant is left exactly whole rather than a pesewa
// short. An effective rate of zero (or, defensively, one at or above 100%)
// leaves the amount untouched.
func grossUp(amount int64, effectiveBps int64) int64 {
	denominator := 10000 - effectiveBps
	if denominator <= 0 || denominator >= 10000 {
		return amount
	}
	return (amount*10000 + denominator/2) / denominator
}

func computeInvoiceAmounts(subtotal int64, p pricing, allocation string, splitBps pgtype.Int4, deliveryFeePesewas int64, deliveryBundled bool) invoiceAmounts {
	// base is what the merchant is asking to receive: goods, plus a bundled
	// delivery fee (collected on their behalf and paid out to them, see
	// ComputeSettlementAggregate). An "external" delivery fee is settled
	// directly between customer and courier and never reaches the invoice
	// total, so it is not part of the base.
	base := subtotal
	if deliveryBundled {
		base += deliveryFeePesewas
	}
	if base <= 0 {
		return invoiceAmounts{}
	}

	shareBps := customerCommissionShareBps(allocation, splitBps)

	// The gross-up depends on which side of the clamps the margin lands, and
	// that depends on the total the gross-up produces. Solve the unclamped
	// case first, then re-solve against whichever clamp it turns out to hit:
	// with the margin pinned to a constant, the remaining rate is just the
	// pass-through, and the pinned amount grosses up alongside the base.
	total := grossUp(base, int64(p.commissionBps())*shareBps/10000)
	collectionOnlyBps := int64(p.CollectionFeeBps) * shareBps / 10000

	switch margin := total * int64(p.MarginBps) / 10000; {
	case margin < p.MarginFloor:
		total = grossUp(base+p.MarginFloor*shareBps/10000, collectionOnlyBps)
	case p.MarginCap > 0 && margin > p.MarginCap:
		total = grossUp(base+p.MarginCap*shareBps/10000, collectionOnlyBps)
	}

	margin := total * int64(p.MarginBps) / 10000
	if margin < p.MarginFloor {
		margin = p.MarginFloor
	}
	if p.MarginCap > 0 && margin > p.MarginCap {
		margin = p.MarginCap
	}

	// The PSP share truncates rather than rounding up, leaving the sub-pesewa
	// remainder with OrderxPay instead of shaving the merchant payout.
	commission := total*int64(p.CollectionFeeBps)/10000 + margin
	if commission > total {
		// Only reachable on an invoice small enough that the margin floor
		// exceeds the whole thing (a ₵0.10 sale against a ₵0.20 floor).
		// Taking more than was collected would push the merchant payout
		// negative, so the floor gives way instead.
		commission = total
	}

	return invoiceAmounts{
		CommissionPesewas:    commission,
		ServiceChargePesewas: total - base,
		TotalPesewas:         total,
	}
}

// pricingForMerchant resolves the applicable fee rule: a merchant-specific
// override if one exists, else the platform default (Section 7.4).
func (h *Handler) pricingForMerchant(ctx context.Context, merchantID pgtype.UUID) (pricing, error) {
	rule, err := h.Queries.GetFeeRuleByMerchant(ctx, merchantID)
	if errors.Is(err, pgx.ErrNoRows) {
		rule, err = h.Queries.GetGlobalFeeRule(ctx)
		if errors.Is(err, pgx.ErrNoRows) {
			return pricing{}, errors.New("no fee rule configured — set a global default via POST /api/v1/admin/fee-rules/global")
		}
	}
	if err != nil {
		return pricing{}, err
	}
	// A blended rate at or above 100% makes the customer-borne gross-up
	// unsolvable, and is a configuration mistake rather than a pricing
	// choice — the fee_rules CHECK constraints only enforce lower bounds.
	if rule.CollectionFeeBps < 0 || rule.MarginBps < 0 ||
		rule.CollectionFeeBps+rule.MarginBps >= 10000 {
		return pricing{}, fmt.Errorf("fee rule is out of range: collection %d bps + margin %d bps must be non-negative and under 10000 bps (100%%)",
			rule.CollectionFeeBps, rule.MarginBps)
	}
	return pricing{
		CollectionFeeBps: rule.CollectionFeeBps,
		MarginBps:        rule.MarginBps,
		MarginFloor:      rule.MarginFloorPesewas,
		MarginCap:        rule.MarginCapPesewas,
	}, nil
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
	CustomerName        pgtype.Text // optional — not stored on the invoice itself, only used to save/update the customers row (see insertInvoice)
	LineItems           []lineItemRequest
	DeliveryOptionID    pgtype.UUID
	DeliveryAddress     string
	DeliveryFeeHandling string // "bundled" | "external" | ""
	DeliveryFeePesewas  int64
	PickupLocationID    pgtype.UUID // feedback item 4 — optional reference pickup point
}

const maxReferenceAttempts = 3

// createInvoiceCore is the shared engine behind both CreateInvoice and
// confirming an order request (Section 4.6) into a payable invoice.
func (h *Handler) createInvoiceCore(ctx context.Context, p createInvoiceCoreParams) (db.Invoice, []db.InvoiceLineItem, error) {
	merchant, err := h.Queries.GetMerchant(ctx, p.MerchantID)
	if err != nil {
		return db.Invoice{}, nil, fmt.Errorf("load merchant: %w", err)
	}
	if merchant.Status == "suspended" {
		return db.Invoice{}, nil, newValidationError("merchant is suspended and cannot create new invoices")
	}

	resolvedLines, subtotal, err := h.resolveLineItems(ctx, p.MerchantID, p.LineItems)
	if err != nil {
		return db.Invoice{}, nil, err
	}

	price, err := h.pricingForMerchant(ctx, p.MerchantID)
	if err != nil {
		return db.Invoice{}, nil, err
	}

	deliveryBundled := p.DeliveryFeeHandling == "bundled"
	amounts := computeInvoiceAmounts(subtotal, price, merchant.ServiceChargeAllocation, merchant.ServiceChargeSplitBps, p.DeliveryFeePesewas, deliveryBundled)

	// KYC tier limits (Section 4.1), checked on the computed total rather
	// than the caller's numbers, and before anything is inserted so there
	// is no half-made invoice to clean up. Sitting here rather than in
	// CreateInvoice covers every path that raises an invoice — the app, an
	// accepted order request, WhatsApp — instead of only the HTTP one.
	//
	// This is the merchant-facing half of the check: they hear about the
	// limit while the invoice is still theirs to change. The binding check
	// is in InitiateCheckoutPayment, since an invoice can be raised under
	// the cap and paid after other collections have consumed it.
	if msg, err := h.enforceTierLimitFor(ctx, p.MerchantID, merchant.KycTier, amounts.TotalPesewas); err != nil {
		return db.Invoice{}, nil, fmt.Errorf("check kyc tier limits: %w", err)
	} else if msg != "" {
		return db.Invoice{}, nil, newValidationError("%s", msg)
	}

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
		PickupLocationID:        p.PickupLocationID,
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

	// Best-effort (same posture as the order-request notification write) —
	// never fail the actual sale over a customers-list write. Outside the
	// transaction on purpose: this is bookkeeping for the merchant's saved
	// customers list, not part of what makes the invoice itself valid.
	if _, err := h.Queries.UpsertCustomer(ctx, db.UpsertCustomerParams{
		MerchantID: p.MerchantID,
		Contact:    p.CustomerContact,
		Name:       p.CustomerName,
	}); err != nil {
		log.Printf("invoice %s: failed to save customer %s: %v", invoice.ID, p.CustomerContact, err)
	}

	return invoice, lineItems, nil
}
