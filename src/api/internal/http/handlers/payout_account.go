package handlers

import (
	"context"
	"errors"
	"fmt"
	"log"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	db "github.com/orderxpay/api/internal/db/sqlc"
	"github.com/orderxpay/api/internal/psp"
)

// Section 4.1/7.2: closes the loop on "Payout account (Mobile Money/Bank)",
// which the app has shown as a permanently-unchecked box since payout_
// account_type/payout_account_ref were added to the schema — collected
// nowhere until this file.
//
// The name-match: Paystack's account resolution returns the name actually
// on file with the bank or mobile network for a given account number,
// independent of anything the merchant types. That's what's compared
// against — never a name the merchant supplies, which would make the check
// worthless (a typo in the account number and a typo in a hand-entered name
// can agree with each other while both are wrong). Two calls exist:
//
//	ResolvePayoutAccount  preview — resolves and returns the name, no save.
//	                       Safe to call while a merchant is still typing or
//	                       correcting a digit.
//	SetPayoutAccount      resolves AGAIN server-side and saves. Never trusts
//	                       a client-supplied account_name: skipping straight
//	                       to this endpoint with an invented name is not a
//	                       way to bypass verification, because the name
//	                       that gets stored is always freshly resolved here,
//	                       not whatever the caller sent.
//
// bankTypeForAccountType maps this app's momo|bank vocabulary onto
// Paystack's mobile_money|ghipss bank "type" filter.
func bankTypeForAccountType(accountType string) (string, error) {
	switch accountType {
	case "momo":
		return psp.BankTypeMobileMoney, nil
	case "bank":
		return psp.BankTypeGhipss, nil
	default:
		return "", errors.New("account_type must be momo or bank")
	}
}

// ListPayoutBanks backs the network/bank picker a merchant sees before
// entering an account number — GET .../payout-account/banks?account_type=momo|bank.
func (h *Handler) ListPayoutBanks(c *fiber.Ctx) error {
	bankType, err := bankTypeForAccountType(c.Query("account_type"))
	if err != nil {
		return badRequest(c, err.Error())
	}

	pspClient := h.paystackClient(c.Context())
	if !pspClient.Enabled() {
		return notImplemented(c, "payout verification is not configured — set PAYSTACK_SECRET_KEY")
	}

	banks, err := pspClient.ListBanks(c.Context(), "GHS", bankType)
	if err != nil {
		return c.Status(fiber.StatusBadGateway).JSON(fiber.Map{"error": "failed to load banks from provider"})
	}
	return c.JSON(banks)
}

type payoutAccountRequest struct {
	AccountType   string `json:"account_type"`   // momo | bank
	AccountNumber string `json:"account_number"` // wallet number (momo) or account number (bank)
	BankCode      string `json:"bank_code"`      // from ListPayoutBanks
}

func (r *payoutAccountRequest) normalize() {
	r.AccountType = strings.TrimSpace(r.AccountType)
	r.AccountNumber = strings.TrimSpace(r.AccountNumber)
	r.BankCode = strings.TrimSpace(r.BankCode)
}

func (r payoutAccountRequest) validate() error {
	if _, err := bankTypeForAccountType(r.AccountType); err != nil {
		return err
	}
	if r.AccountNumber == "" {
		return errors.New("account_number is required")
	}
	if r.BankCode == "" {
		return errors.New("bank_code is required")
	}
	return nil
}

// ResolvePayoutAccount previews the account holder's name Paystack has on
// file, without saving anything (Section 4.1). The merchant app shows this
// name and asks "is this you?" before the second call actually attaches it
// to the merchant.
func (h *Handler) ResolvePayoutAccount(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	var req payoutAccountRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	req.normalize()
	if err := req.validate(); err != nil {
		return badRequest(c, err.Error())
	}

	if _, err := h.Queries.GetMerchant(c.Context(), merchantID); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return notFound(c)
		}
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load merchant"})
	}

	pspClient := h.paystackClient(c.Context())
	if !pspClient.Enabled() {
		return notImplemented(c, "payout verification is not configured — set PAYSTACK_SECRET_KEY")
	}

	result, err := pspClient.ResolveAccount(c.Context(), req.AccountNumber, req.BankCode)
	if err != nil {
		// A resolve failure almost always means the account number or
		// bank/network doesn't match anything real — that is useful,
		// actionable information for the merchant, not a server error, so
		// it's surfaced as a 400 rather than a 502.
		return badRequest(c, "could not verify that account — check the number and network/bank and try again")
	}
	return c.JSON(fiber.Map{"account_name": result.AccountName})
}

// SetPayoutAccount attaches a verified payout destination to the merchant
// (Section 4.1). Always re-resolves server-side before saving — see the
// package doc comment above for why a client-supplied account_name is never
// trusted, at either call.
func (h *Handler) SetPayoutAccount(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}

	var req payoutAccountRequest
	if err := c.BodyParser(&req); err != nil {
		return badRequest(c, "invalid request body")
	}
	req.normalize()
	if err := req.validate(); err != nil {
		return badRequest(c, err.Error())
	}

	if _, err := h.Queries.GetMerchant(c.Context(), merchantID); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return notFound(c)
		}
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load merchant"})
	}

	pspClient := h.paystackClient(c.Context())
	if !pspClient.Enabled() {
		return notImplemented(c, "payout verification is not configured — set PAYSTACK_SECRET_KEY")
	}

	result, err := pspClient.ResolveAccount(c.Context(), req.AccountNumber, req.BankCode)
	if err != nil {
		return badRequest(c, "could not verify that account — check the number and network/bank and try again")
	}

	merchant, err := h.Queries.UpdateMerchantPayoutAccount(c.Context(), db.UpdateMerchantPayoutAccountParams{
		ID:                      merchantID,
		PayoutAccountType:       pgtype.Text{String: req.AccountType, Valid: true},
		PayoutAccountRef:        pgtype.Text{String: req.AccountNumber, Valid: true},
		PayoutBankCode:          pgtype.Text{String: req.BankCode, Valid: true},
		PayoutAccountName:       pgtype.Text{String: result.AccountName, Valid: true},
		PayoutAccountVerifiedAt: pgtype.Timestamptz{Time: time.Now(), Valid: true},
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to save payout account"})
	}

	// Not routed through writeAdminAuditLog: this is a merchant
	// self-service action (own merchant/staff token, same route shape as
	// UpdateMerchantFeeSettings/UpdateMerchantWhatsAppSettings, neither of
	// which audit-log either), and that helper hardcodes ActorType to
	// auth.ActorUser — using it here would mislabel a merchant's own action
	// as a Back Office user's in the audit trail, which is worse than not
	// logging at all.

	// Section 7's split-payments prerequisite: provision (or repoint) the
	// merchant's Paystack subaccount now, so switching split payments on
	// for them later needs zero additional setup and can't lag behind
	// whichever payout account is actually current. Best-effort — a
	// merchant is still correctly payout-verified for the ordinary manual-
	// settlement path either way, and re-saving their payout account
	// (e.g. on their next edit) retries this automatically.
	if provisioned, err := h.provisionSubaccount(c.Context(), merchant, pspClient); err != nil {
		log.Printf("paystack: failed to provision subaccount for merchant %s: %v", merchantID, err)
	} else {
		merchant = provisioned
	}
	return c.JSON(stripMerchantSecrets(merchant))
}

// provisionSubaccount creates the merchant's Paystack subaccount if they
// don't have one, or repoints an existing one at their (possibly just-
// changed) verified payout account — always the current
// PayoutAccountRef/PayoutBankCode, since a subaccount pointed at a stale
// account would silently keep sending a future split payment's merchant
// share to money that's no longer theirs.
//
// The percentage_charge sent here is a fallback only — see
// psp.SubaccountParams' doc comment on why it never actually decides a
// transaction's split in this codebase.
func (h *Handler) provisionSubaccount(ctx context.Context, merchant db.Merchant, pspClient *psp.Client) (db.Merchant, error) {
	price, err := h.pricingForMerchant(ctx, merchant.ID)
	if err != nil {
		return db.Merchant{}, fmt.Errorf("load pricing: %w", err)
	}

	params := psp.SubaccountParams{
		BusinessName:     merchant.BusinessName,
		SettlementBank:   merchant.PayoutBankCode.String,
		AccountNumber:    merchant.PayoutAccountRef.String,
		PercentageCharge: float64(price.CollectionFeeBps+price.MarginBps) / 100,
	}

	var sub *psp.Subaccount
	if merchant.PaystackSubaccountCode.Valid && merchant.PaystackSubaccountCode.String != "" {
		sub, err = pspClient.UpdateSubaccount(ctx, merchant.PaystackSubaccountCode.String, params)
	} else {
		sub, err = pspClient.CreateSubaccount(ctx, params)
	}
	if err != nil {
		return db.Merchant{}, err
	}

	return h.Queries.UpdateMerchantSubaccountCode(ctx, db.UpdateMerchantSubaccountCodeParams{
		ID:                     merchant.ID,
		PaystackSubaccountCode: pgtype.Text{String: sub.SubaccountCode, Valid: true},
	})
}
