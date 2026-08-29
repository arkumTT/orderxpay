// Package sms wraps Arkesel's SMS v2 API (https://sms.arkesel.com/api/v2/sms/send)
// — chosen as a Ghana-focused provider with a plain REST API and no SDK
// dependency, per the recommendation given when this integration was
// scoped (feedback: "no SMS provider account yet, recommend one"). The
// core request/response shape below (api-key header, sender/message/
// recipients body, {"status":"success","data":{...}} on success) is
// confirmed against Arkesel's public docs as of the time this was written;
// their documented error-response shape wasn't fully available at that
// time, so failure handling here is deliberately defensive — any non-2xx
// or a body whose "status" isn't "success" is treated as a failure with
// the raw response body surfaced in the error, rather than parsing
// specific error fields that might not match their real schema. Verify
// against your live Arkesel dashboard/docs before this carries real
// traffic, and adjust the error parsing if their actual error shape
// differs.
//
// A different provider (Hubtel, mNotify, Africa's Talking, Twilio, ...)
// is a straightforward swap: this package's public surface (NewClient,
// Enabled, Send) is the only thing callers touch.
package sms

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"time"
)

const defaultAPIURL = "https://sms.arkesel.com/api/v2/sms/send"

type Client struct {
	APIKey     string
	SenderID   string
	APIURL     string
	HTTPClient *http.Client
}

// NewClient builds an SMS client. senderID is the alphanumeric Sender ID
// Ghana's regulator (NCA) requires to be registered with the SMS provider
// before it'll actually deliver — check current registration requirements
// with Arkesel directly, this codebase doesn't (and can't) enforce that.
func NewClient(apiKey, senderID string) *Client {
	return &Client{
		APIKey:     apiKey,
		SenderID:   senderID,
		APIURL:     defaultAPIURL,
		HTTPClient: &http.Client{Timeout: 15 * time.Second},
	}
}

// Enabled reports whether an API key has been configured. Callers should
// skip sending (not error loudly) when false, the same graceful-degrade
// posture as psp.Client.Enabled() and whatsapp.Client.Enabled().
func (c *Client) Enabled() bool {
	return c != nil && c.APIKey != ""
}

type sendRequest struct {
	Sender     string   `json:"sender"`
	Message    string   `json:"message"`
	Recipients []string `json:"recipients"`
}

type sendResponse struct {
	Status string `json:"status"`
	Data   struct {
		ID          string `json:"id"`
		CreditsUsed int    `json:"credits_used"`
	} `json:"data"`
}

// Send delivers a single SMS to one recipient. to should be in E.164 form
// (e.g. "+233244000000") — Arkesel's docs show the leading "+".
func (c *Client) Send(ctx context.Context, to, message string) error {
	if !c.Enabled() {
		return errors.New("sms: api key not configured")
	}
	if to == "" {
		return errors.New("sms: recipient is required")
	}

	reqBody, err := json.Marshal(sendRequest{
		Sender:     c.SenderID,
		Message:    message,
		Recipients: []string{to},
	})
	if err != nil {
		return err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.APIURL, bytes.NewReader(reqBody))
	if err != nil {
		return err
	}
	req.Header.Set("api-key", c.APIKey)
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
		return fmt.Errorf("sms: send returned %d: %s", res.StatusCode, string(respBody))
	}

	var result sendResponse
	if err := json.Unmarshal(respBody, &result); err != nil {
		return fmt.Errorf("sms: could not parse response: %s", string(respBody))
	}
	if result.Status != "success" {
		return fmt.Errorf("sms: send failed: %s", string(respBody))
	}
	return nil
}
