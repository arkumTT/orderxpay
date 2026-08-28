// Package whatsapp wraps Meta's WhatsApp Cloud API directly (Section
// 4.4/6.2/7.3) — no BSP middleman, since no vendor has been chosen (the
// architecture doc's whatsapp_bsp integration is a placeholder for that
// open decision, not a commitment). One access token (a Meta System User
// token, account-level) works across every phone number registered under
// the platform's WhatsApp Business Account — see handlers/whatsapp.go for
// how an inbound message gets attributed to a merchant by phone_number_id
// rather than by a per-merchant credential.
package whatsapp

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

const (
	apiVersion = "v21.0"
	baseURL    = "https://graph.facebook.com/" + apiVersion
)

type Client struct {
	AccessToken string
	HTTPClient  *http.Client
}

func NewClient(accessToken string) *Client {
	return &Client{
		AccessToken: accessToken,
		HTTPClient:  &http.Client{Timeout: 15 * time.Second},
	}
}

// Enabled reports whether an access token has been configured. Callers
// should skip sending (not error loudly) when false — an unconfigured
// WhatsApp client just means auto-reply silently doesn't fire yet, the
// same graceful-degrade posture as psp.Client.Enabled().
func (c *Client) Enabled() bool {
	return c != nil && c.AccessToken != ""
}

type SendTextParams struct {
	// PhoneNumberID is the Meta-assigned ID of the merchant's own number
	// under the platform WABA — not the number itself, and not shared
	// across merchants.
	PhoneNumberID string
	To            string // recipient, E.164 without a leading "+" per Meta's convention
	Body          string
}

type sendResult struct {
	Messages []struct {
		ID string `json:"id"`
	} `json:"messages"`
}

// SendText sends a plain session message — only valid within Meta's
// 24-hour customer-service window (i.e. replying to an inbound message),
// which is the only case this codebase uses it for today (Section 4.4
// auto-reply). A business-initiated message outside that window needs a
// pre-approved template instead; this client doesn't implement that path
// yet since nothing in this codebase sends proactively.
func (c *Client) SendText(ctx context.Context, p SendTextParams) (string, error) {
	if !c.Enabled() {
		return "", errors.New("whatsapp: access token not configured")
	}
	if p.PhoneNumberID == "" {
		return "", errors.New("whatsapp: phone_number_id is required")
	}

	body, err := json.Marshal(map[string]any{
		"messaging_product": "whatsapp",
		"to":                p.To,
		"type":              "text",
		"text":              map[string]any{"body": p.Body},
	})
	if err != nil {
		return "", err
	}

	var result sendResult
	if err := c.do(ctx, http.MethodPost, "/"+p.PhoneNumberID+"/messages", body, &result); err != nil {
		return "", err
	}
	if len(result.Messages) == 0 {
		return "", errors.New("whatsapp: send succeeded but no message id returned")
	}
	return result.Messages[0].ID, nil
}

func (c *Client) do(ctx context.Context, method, path string, body []byte, out any) error {
	var reader io.Reader
	if body != nil {
		reader = bytes.NewReader(body)
	}
	req, err := http.NewRequestWithContext(ctx, method, baseURL+path, reader)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+c.AccessToken)
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
		return fmt.Errorf("whatsapp: %s %s returned %d: %s", method, path, res.StatusCode, string(respBody))
	}
	return json.Unmarshal(respBody, out)
}

// VerifyWebhookSignature checks the X-Hub-Signature-256 header Meta sends
// on every webhook delivery: "sha256=" followed by the hex HMAC-SHA256 of
// the raw body, keyed with the app secret (not the access token — a
// different credential, from the Meta App's Basic Settings). Must run
// against the raw bytes before any JSON parsing/re-marshaling, same
// requirement as psp.VerifyWebhookSignature.
func VerifyWebhookSignature(appSecret string, rawBody []byte, signatureHeader string) bool {
	const prefix = "sha256="
	if appSecret == "" || !strings.HasPrefix(signatureHeader, prefix) {
		return false
	}
	sig := strings.TrimPrefix(signatureHeader, prefix)
	mac := hmac.New(sha256.New, []byte(appSecret))
	mac.Write(rawBody)
	expected := hex.EncodeToString(mac.Sum(nil))
	return hmac.Equal([]byte(expected), []byte(sig))
}
