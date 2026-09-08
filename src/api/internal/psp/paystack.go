// Package psp wraps the Paystack API (Section 9.1) — the PSP selected for
// initial integration because Ghana test/sandbox keys require no business
// vetting to obtain, and its hosted checkout page handles MoMo/card channel
// selection itself rather than requiring a separate integration per rail.
package psp

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha512"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"
)

const baseURL = "https://api.paystack.co"

type Client struct {
	SecretKey  string
	HTTPClient *http.Client
}

func NewClient(secretKey string) *Client {
	return &Client{
		SecretKey:  secretKey,
		HTTPClient: &http.Client{Timeout: 15 * time.Second},
	}
}

// Enabled reports whether a secret key has been configured. Callers should
// reject payment-initiation requests with a clear error when false rather
// than letting every Paystack call fail with an opaque 401.
func (c *Client) Enabled() bool {
	return c != nil && c.SecretKey != ""
}

type InitializeParams struct {
	Email         string
	AmountPesewas int64 // Paystack takes amounts in the lowest currency unit, same as our own pesewas
	Currency      string
	Reference     string
	CallbackURL   string

	// Subaccount and TransactionChargePesewas together are how a payment
	// is split at charge time (Section 7's "Paystack subaccounts and split
	// payments") — the merchant's share settles straight to their own
	// Paystack subaccount, OrderxPay's commission to the main account.
	// Leave Subaccount empty for the ordinary, non-split path (everything
	// lands in OrderxPay's own balance, exactly as before this existed).
	//
	// TransactionChargePesewas is REQUIRED whenever Subaccount is set —
	// InitializeTransaction refuses to send one without the other. A
	// subaccount also carries its own percentage_charge, set at creation,
	// which Paystack would otherwise use as a fallback split — but this
	// codebase computes the exact commission per invoice (floor/cap-
	// clamped, not a flat rate; see invoice_engine.go) and must never let
	// a stale static percentage decide real money movement.
	Subaccount               string
	TransactionChargePesewas int64
}

type InitializeResult struct {
	AuthorizationURL string `json:"authorization_url"`
	AccessCode       string `json:"access_code"`
	Reference        string `json:"reference"`
}

type paystackEnvelope[T any] struct {
	Status  bool   `json:"status"`
	Message string `json:"message"`
	Data    T      `json:"data"`
}

// errSplitRequiresTransactionCharge is a sentinel so callers (and this
// package's own tests) can check for exactly this guardrail firing,
// without string-matching an error message.
var errSplitRequiresTransactionCharge = errors.New("paystack: a subaccount split requires an explicit transaction_charge")

// validateInitializeParams is InitializeTransaction's structural guardrail,
// pulled out as a pure function so it's testable without a network call:
// splitting without an explicit flat fee would fall back to the
// subaccount's own static percentage_charge, which this codebase never
// wants deciding real money movement (see InitializeParams' doc comment).
// Refusing here means a caller can't accidentally split on Paystack's
// fallback rate by forgetting one field.
func validateInitializeParams(p InitializeParams) error {
	if p.Subaccount != "" && p.TransactionChargePesewas <= 0 {
		return errSplitRequiresTransactionCharge
	}
	return nil
}

func (c *Client) InitializeTransaction(ctx context.Context, p InitializeParams) (*InitializeResult, error) {
	if err := validateInitializeParams(p); err != nil {
		return nil, err
	}

	payload := map[string]any{
		"email":        p.Email,
		"amount":       p.AmountPesewas,
		"currency":     p.Currency,
		"reference":    p.Reference,
		"callback_url": p.CallbackURL,
	}
	if p.Subaccount != "" {
		payload["subaccount"] = p.Subaccount
		payload["transaction_charge"] = p.TransactionChargePesewas
		// Deliberately omitted: "bearer". Its default ("account") means
		// OrderxPay's main account absorbs Paystack's real processing
		// fee — which is correct here, because that cost is already
		// priced into the commission taken via transaction_charge (see
		// pricing.CollectionFeeBps in invoice_engine.go). Setting
		// bearer=subaccount would charge the merchant Paystack's fee a
		// second time, on top of the commission that already accounts
		// for it.
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}

	var env paystackEnvelope[InitializeResult]
	if err := c.do(ctx, http.MethodPost, "/transaction/initialize", body, &env); err != nil {
		return nil, err
	}
	if !env.Status {
		return nil, fmt.Errorf("paystack: initialize failed: %s", env.Message)
	}
	return &env.Data, nil
}

type VerifyResult struct {
	Status          string `json:"status"` // "success" | "failed" | "abandoned" | ...
	Reference       string `json:"reference"`
	Amount          int64  `json:"amount"`
	Currency        string `json:"currency"`
	GatewayResponse string `json:"gateway_response"`
	Channel         string `json:"channel"` // "card" | "mobile_money" | ...
	// Fees is nil when Paystack hasn't reported a fee for this transaction
	// (observed on some test-mode charges) — callers should treat that as
	// "unknown," not "zero," when it matters for reporting.
	Fees *int64 `json:"fees"`
}

func (c *Client) VerifyTransaction(ctx context.Context, reference string) (*VerifyResult, error) {
	var env paystackEnvelope[VerifyResult]
	path := "/transaction/verify/" + reference
	if err := c.do(ctx, http.MethodGet, path, nil, &env); err != nil {
		return nil, err
	}
	if !env.Status {
		return nil, fmt.Errorf("paystack: verify failed: %s", env.Message)
	}
	return &env.Data, nil
}

type RefundResult struct {
	Status               string `json:"status"` // "pending" | "processed" | "failed" | ...
	Amount               int64  `json:"amount"`
	Currency             string `json:"currency"`
	TransactionReference string `json:"transaction_reference"`
}

// RefundTransaction issues a refund against a prior charge (Section 7.7).
// AmountPesewas is required — dispute resolution always refunds a specific
// payment for a specific amount the reviewer chose, never "whatever the
// original charge was," so there's no implicit full-refund path here.
func (c *Client) RefundTransaction(ctx context.Context, reference string, amountPesewas int64) (*RefundResult, error) {
	body, err := json.Marshal(map[string]any{
		"transaction": reference,
		"amount":      amountPesewas,
	})
	if err != nil {
		return nil, err
	}

	var env paystackEnvelope[RefundResult]
	if err := c.do(ctx, http.MethodPost, "/refund", body, &env); err != nil {
		return nil, err
	}
	if !env.Status {
		return nil, fmt.Errorf("paystack: refund failed: %s", env.Message)
	}
	return &env.Data, nil
}

// Bank is one entry from ListBanks — a bank or, in Ghana, a mobile money
// network (MTN, Telecel Cash, AirtelTigo Money), which Paystack exposes
// through the same endpoint distinguished by Type. Only Name and Code are
// used by this codebase; other fields Paystack returns are ignored rather
// than modeled.
type Bank struct {
	Name string `json:"name"`
	Code string `json:"code"`
	Type string `json:"type"` // "ghipss" (bank) | "mobile_money", for GHS
}

// BankType values for ListBanks' typeFilter and ResolveAccount's bankCode
// namespace — Paystack Ghana's two payout rails.
const (
	BankTypeGhipss      = "ghipss"
	BankTypeMobileMoney = "mobile_money"
)

// ListBanks returns the banks or mobile money networks Paystack supports
// for currency (use "GHS"), filtered to typeFilter (BankTypeGhipss or
// BankTypeMobileMoney) — this is the picker a merchant chooses their
// network/bank from before entering an account number.
func (c *Client) ListBanks(ctx context.Context, currency, typeFilter string) ([]Bank, error) {
	path := fmt.Sprintf("/bank?currency=%s&type=%s", currency, typeFilter)
	var env paystackEnvelope[[]Bank]
	if err := c.do(ctx, http.MethodGet, path, nil, &env); err != nil {
		return nil, err
	}
	if !env.Status {
		return nil, fmt.Errorf("paystack: list banks failed: %s", env.Message)
	}
	return env.Data, nil
}

type ResolveAccountResult struct {
	AccountNumber string `json:"account_number"`
	// AccountName is the name Paystack has on file for this account —
	// resolved from the bank/mobile network, never from anything the
	// caller supplied. This is the entire point of the call: comparing an
	// independently-resolved name against what the merchant expects is
	// what catches a mistyped account number before money moves, per
	// Paystack's account verification API (available for Nigeria and
	// Ghana, free to call).
	AccountName string `json:"account_name"`
}

// ResolveAccount verifies accountNumber against bankCode (a code from
// ListBanks — either a GHIPSS bank code or a mobile money network code) and
// returns the account holder's name on file. Read-only: unlike creating a
// transfer recipient, this has no side effect on the Paystack side, so it's
// safe to call speculatively while a merchant is still typing/correcting
// their account number.
func (c *Client) ResolveAccount(ctx context.Context, accountNumber, bankCode string) (*ResolveAccountResult, error) {
	path := fmt.Sprintf("/bank/resolve?account_number=%s&bank_code=%s", url.QueryEscape(accountNumber), url.QueryEscape(bankCode))
	var env paystackEnvelope[ResolveAccountResult]
	if err := c.do(ctx, http.MethodGet, path, nil, &env); err != nil {
		return nil, err
	}
	if !env.Status {
		return nil, fmt.Errorf("paystack: resolve account failed: %s", env.Message)
	}
	return &env.Data, nil
}

// SubaccountParams is what CreateSubaccount and UpdateSubaccount send.
// AccountNumber/SettlementBank should already be independently verified —
// this codebase always passes the exact values already confirmed by
// ResolveAccount (see payout_account.go), never anything freshly typed.
type SubaccountParams struct {
	BusinessName   string
	SettlementBank string // bank/network code, same one used with ResolveAccount
	AccountNumber  string
	// PercentageCharge is the percentage Paystack's docs describe as
	// "charged when receiving on behalf of this subaccount" — read here as
	// the share the MAIN account (OrderxPay) keeps, corroborated by
	// Paystack's own worked examples but not spelled out unambiguously in
	// their reference docs. This field is NEVER what actually decides a
	// real transaction's split in this codebase — every split payment
	// passes an explicit TransactionChargePesewas instead (see
	// InitializeParams), which always wins. Treat this purely as the
	// subaccount's cosmetic default in Paystack's own dashboard, and
	// confirm the direction against a live test-mode account before
	// leaning on it for anything real.
	PercentageCharge float64
}

type Subaccount struct {
	SubaccountCode string `json:"subaccount_code"`
	AccountName    string `json:"account_name"`
}

func (p SubaccountParams) body() ([]byte, error) {
	return json.Marshal(map[string]any{
		"business_name":     p.BusinessName,
		"settlement_bank":   p.SettlementBank,
		"account_number":    p.AccountNumber,
		"percentage_charge": p.PercentageCharge,
	})
}

// CreateSubaccount provisions the Paystack object a payment can later be
// split into (Section 7's "Paystack subaccounts and split payments").
// Creating one has no effect on how any existing or future payment is
// routed by itself — only passing its SubaccountCode as
// InitializeParams.Subaccount does that.
func (c *Client) CreateSubaccount(ctx context.Context, p SubaccountParams) (*Subaccount, error) {
	body, err := p.body()
	if err != nil {
		return nil, err
	}
	var env paystackEnvelope[Subaccount]
	if err := c.do(ctx, http.MethodPost, "/subaccount", body, &env); err != nil {
		return nil, err
	}
	if !env.Status {
		return nil, fmt.Errorf("paystack: create subaccount failed: %s", env.Message)
	}
	return &env.Data, nil
}

// UpdateSubaccount repoints an existing subaccount at (possibly) different
// settlement details — used when a merchant changes their verified payout
// account after a subaccount already exists for them, so split proceeds
// never keep flowing to a stale account.
func (c *Client) UpdateSubaccount(ctx context.Context, subaccountCode string, p SubaccountParams) (*Subaccount, error) {
	body, err := p.body()
	if err != nil {
		return nil, err
	}
	var env paystackEnvelope[Subaccount]
	if err := c.do(ctx, http.MethodPut, "/subaccount/"+url.PathEscape(subaccountCode), body, &env); err != nil {
		return nil, err
	}
	if !env.Status {
		return nil, fmt.Errorf("paystack: update subaccount failed: %s", env.Message)
	}
	return &env.Data, nil
}

func (c *Client) do(ctx context.Context, method, path string, body []byte, out any) error {
	if !c.Enabled() {
		return errors.New("paystack: secret key not configured")
	}

	var reader io.Reader
	if body != nil {
		reader = bytes.NewReader(body)
	}
	req, err := http.NewRequestWithContext(ctx, method, baseURL+path, reader)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+c.SecretKey)
	req.Header.Set("Content-Type", "application/json")

	res, err := c.HTTPClient.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()

	respBody, err := io.ReadAll(res.Body)
	if err != nil {
		return err
	}
	if res.StatusCode >= 400 {
		return fmt.Errorf("paystack: %s %s returned %d: %s", method, path, res.StatusCode, string(respBody))
	}
	return json.Unmarshal(respBody, out)
}

// VerifyWebhookSignature checks the x-paystack-signature header: HMAC-SHA512
// of the raw request body, keyed with the account's secret key. Must run
// against the raw bytes before any JSON parsing/re-marshaling, since
// re-encoding can change byte-for-byte formatting and break the signature.
func VerifyWebhookSignature(secretKey string, rawBody []byte, signatureHeader string) bool {
	if secretKey == "" || signatureHeader == "" {
		return false
	}
	mac := hmac.New(sha512.New, []byte(secretKey))
	mac.Write(rawBody)
	expected := hex.EncodeToString(mac.Sum(nil))
	return hmac.Equal([]byte(expected), []byte(signatureHeader))
}
