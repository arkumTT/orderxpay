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

func (c *Client) InitializeTransaction(ctx context.Context, p InitializeParams) (*InitializeResult, error) {
	body, err := json.Marshal(map[string]any{
		"email":        p.Email,
		"amount":       p.AmountPesewas,
		"currency":     p.Currency,
		"reference":    p.Reference,
		"callback_url": p.CallbackURL,
	})
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
