// Package hubtel wraps Hubtel's Receive Money (mobile money / USSD) API —
// the fallback payment rail for a customer who can't complete Paystack's
// hosted checkout page at all: no smartphone, no data, no browser. Instead
// of a link the customer opens, a Hubtel-initiated request sends a USSD/PIN
// prompt straight to their phone over the ordinary GSM signaling channel,
// which works on any phone on any network.
//
// UNCONFIRMED, READ BEFORE THIS CARRIES REAL TRAFFIC: unlike internal/psp,
// which was built and then verified against Paystack's public docs and a
// real (if only test-mode) account already sitting in this repo's .env,
// this package was written with no Hubtel account to test against at all —
// OrderxPay hasn't signed up for one yet. Hubtel's real technical docs sit
// behind their developer portal (account required), not on a publicly
// crawlable page the way Paystack's are, so nothing here has been checked
// against a primary source the way every claim in internal/psp's doc
// comments was. What follows is the best composite of third-party SDK
// source (PHP/Node community packages) and tutorials that could be found,
// clearly separated by confidence:
//
//   - HIGH confidence (multiple independent sources agree): HTTP Basic Auth
//     with ClientID as username, ClientSecret as password; request field
//     names CustomerName/CustomerMsisdn/CustomerEmail/Channel/Amount/
//     PrimaryCallbackUrl/Description/ClientReference; callback field names
//     TransactionId/ClientReference/Status/ResponseCode/ResponseMessage.
//   - LOW confidence, values that only ever showed up in URL fragments or
//     inferred from a naming convention, never a verbatim primary source:
//     baseURL below, and every value in channelCodes except "mtn-gh".
//
// Confirm both categories against the real docs the moment a Hubtel merchant
// account exists (its dashboard is the authoritative source), before this
// is ever pointed at real traffic — and once it does, the same
// workflow_dispatch-smoke-test pattern in internal/psp/paystack_smoke_test.go
// is the template for verifying it live from a runner with real network,
// the same way the Paystack integration's own unconfirmed details got
// checked.
package hubtel

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"time"
)

// baseURL is the LOW-confidence piece flagged above — composited from
// third-party SDK source referencing "rmp.hubtel.com" and a
// "receive/mobilemoney" path plus a merchant-account-number path segment,
// never confirmed verbatim against a Hubtel-authored source. Treat as a
// placeholder to verify, not a fact.
const baseURL = "https://rmp.hubtel.com/v1/merchantaccount/merchants"

type Client struct {
	ClientID     string
	ClientSecret string
	// POSSalesID is Hubtel's merchant/point-of-sale account identifier —
	// distinct from ClientID/ClientSecret, obtained from the merchant
	// account's own Hubtel dashboard, not the API credentials page.
	POSSalesID string
	HTTPClient *http.Client
}

func NewClient(clientID, clientSecret, posSalesID string) *Client {
	return &Client{
		ClientID:     clientID,
		ClientSecret: clientSecret,
		POSSalesID:   posSalesID,
		HTTPClient:   &http.Client{Timeout: 20 * time.Second},
	}
}

// Enabled reports whether all three required values are configured.
// Callers should skip/reject rather than error loudly when false, the same
// graceful-degrade posture as psp.Client.Enabled().
func (c *Client) Enabled() bool {
	return c != nil && c.ClientID != "" && c.ClientSecret != "" && c.POSSalesID != ""
}

// Channel codes for Hubtel's Receive Money Channel field. "mtn-gh" is the
// one value that showed up verbatim in every source consulted; the other
// two follow the same "{network}-gh" pattern by inference, not
// confirmation — Ghana's telecom rebrand (Vodafone Cash -> Telecel Cash)
// makes "vodafone-gh" a particularly good candidate to have silently
// drifted from whatever Hubtel's API actually expects today.
const (
	ChannelMTN        = "mtn-gh"
	ChannelTelecel    = "vodafone-gh" // UNCONFIRMED — verify; may now be "telecel-gh"
	ChannelAirtelTigo = "tigo-gh"     // UNCONFIRMED — verify
)

type ReceiveMoneyParams struct {
	CustomerName string
	// CustomerMsisdn should be the customer's number in the same local
	// (0XXXXXXXXX) form the rest of this codebase already stores contacts
	// in — not E.164, unlike sms.Client's expected format. Unconfirmed;
	// verify against real docs which literal format Hubtel's API expects.
	CustomerMsisdn string
	CustomerEmail  string
	Channel        string // one of the Channel* constants above
	AmountPesewas  int64
	CallbackURL    string
	Description    string
	// ClientReference must be unique per attempt — Hubtel's own dedup key,
	// playing the same role psp_reference plays for Paystack.
	ClientReference string
}

type hubtelEnvelope struct {
	ResponseCode string          `json:"ResponseCode"`
	Status       string          `json:"Status"`
	Message      string          `json:"Message"`
	Data         json.RawMessage `json:"Data"`
}

type ReceiveMoneyResult struct {
	TransactionID string
	// A USSD/PIN prompt is asynchronous by nature — a 2xx here means the
	// prompt was sent, never that the customer has approved it. The real
	// outcome always arrives later at CallbackURL.
	ResponseCode string
}

// ReceiveMoney sends a USSD/PIN payment prompt to the customer's phone.
// AmountPesewas is converted to a decimal cedi value at this boundary,
// deliberately as late and as narrowly as possible: this codebase never
// uses floats for money anywhere else (schema, application code, API
// payloads all stay integer pesewas — see invoice_engine.go), but Hubtel's
// own wire format takes a decimal amount (every example found shows values
// like 7.55, not subunits the way Paystack's "amount" field works), so the
// float exists for exactly the width of this one JSON field and nowhere
// else — see pesewasToCedis.
func (c *Client) ReceiveMoney(ctx context.Context, p ReceiveMoneyParams) (*ReceiveMoneyResult, error) {
	if !c.Enabled() {
		return nil, errors.New("hubtel: not configured (client id, client secret, and POS sales id are all required)")
	}
	if p.ClientReference == "" {
		return nil, errors.New("hubtel: client_reference is required")
	}

	body, err := json.Marshal(map[string]any{
		"CustomerName":       p.CustomerName,
		"CustomerMsisdn":     p.CustomerMsisdn,
		"CustomerEmail":      p.CustomerEmail,
		"Channel":            p.Channel,
		"Amount":             pesewasToCedis(p.AmountPesewas),
		"PrimaryCallbackUrl": p.CallbackURL,
		"Description":        p.Description,
		"ClientReference":    p.ClientReference,
	})
	if err != nil {
		return nil, err
	}

	url := fmt.Sprintf("%s/%s/receive/mobilemoney", baseURL, c.POSSalesID)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Basic "+basicAuth(c.ClientID, c.ClientSecret))

	res, err := c.HTTPClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()

	respBody, err := io.ReadAll(res.Body)
	if err != nil {
		return nil, err
	}
	if res.StatusCode >= 400 {
		return nil, fmt.Errorf("hubtel: POST %s returned %d: %s", url, res.StatusCode, string(respBody))
	}

	var env hubtelEnvelope
	if err := json.Unmarshal(respBody, &env); err != nil {
		return nil, fmt.Errorf("hubtel: could not parse response: %w (body: %s)", err, string(respBody))
	}
	return &ReceiveMoneyResult{ResponseCode: env.ResponseCode}, nil
}

func basicAuth(clientID, clientSecret string) string {
	return base64.StdEncoding.EncodeToString([]byte(clientID + ":" + clientSecret))
}

// pesewasToCedis converts the integer pesewas this codebase uses
// everywhere else into the decimal cedi value Hubtel's wire format wants,
// rounded to exactly 2 decimal places — the one, narrow, boundary-only
// exception to this codebase's no-floats-for-money rule (see this file's
// package doc comment). Never use this value for anything except the
// literal JSON field sent to Hubtel; every other computation in this
// codebase stays on integer pesewas.
func pesewasToCedis(pesewas int64) float64 {
	return math.Round(float64(pesewas)) / 100
}

// CallbackPayload is what Hubtel POSTs to PrimaryCallbackUrl once the
// customer approves or declines the prompt — field names are the
// HIGH-confidence set from this package's doc comment, but the exact
// Status/ResponseCode values that mean "success" are not independently
// confirmed; see HandleHubtelWebhook's own doc comment in payments.go for
// how that uncertainty is handled defensively rather than guessed at.
type CallbackPayload struct {
	TransactionID   string  `json:"TransactionId"`
	ClientReference string  `json:"ClientReference"`
	InvoiceID       string  `json:"InvoiceId"`
	Amount          float64 `json:"Amount"`
	Status          string  `json:"Status"`
	PaymentMethod   string  `json:"PaymentMethod"`
	CustomerMsisdn  string  `json:"CustomerMsisdn"`
	Description     string  `json:"Description"`
	ResponseCode    string  `json:"ResponseCode"`
	ResponseMessage string  `json:"ResponseMessage"`
}
