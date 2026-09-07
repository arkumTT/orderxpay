// Package fcm wraps Firebase Cloud Messaging (via the official Firebase
// Admin Go SDK) for Section 4.10's push-notification delivery — Phase 2 of
// the Home order-request-visibility work (Phase 1 was the in-app bell +
// banner, built without any push infrastructure). Android only for now:
// iOS push needs a paid Apple Developer Program account and APNs certs,
// which this project doesn't have yet — see the mobile app's Firebase
// project setup notes.
//
// Same nil-safe, graceful-degrade posture as psp.Client/whatsapp.Client/
// sms.Client: NewClient never fails loudly, Enabled() reports whether it's
// actually usable, and callers skip sending rather than erroring when it's
// not configured.
package fcm

import (
	"context"
	"log"
	"os"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"google.golang.org/api/option"
)

type Client struct {
	messaging *messaging.Client
}

// NewClient builds an FCM client from a service account JSON file path
// (FIREBASE_SERVICE_ACCOUNT_JSON — see config.go). An empty path, a
// missing file (the default path is just a sensible guess — most clones
// of this repo won't have the file until someone sets up push), or any
// initialization failure all yield a Client with Enabled() == false
// rather than a startup error, since push notifications are additive
// (Section 4.10's in-app notification feed already works without them).
// A missing file is logged as informational, not an error — anything
// that gets far enough to call firebase.NewApp is a real misconfiguration
// and does get logged loudly.
func NewClient(serviceAccountPath string) *Client {
	if serviceAccountPath == "" {
		return &Client{}
	}
	if _, err := os.Stat(serviceAccountPath); err != nil {
		log.Printf("fcm: no service account at %s, push notifications disabled", serviceAccountPath)
		return &Client{}
	}
	app, err := firebase.NewApp(context.Background(), nil, option.WithCredentialsFile(serviceAccountPath))
	if err != nil {
		log.Printf("fcm: failed to initialize Firebase app: %v", err)
		return &Client{}
	}
	msgClient, err := app.Messaging(context.Background())
	if err != nil {
		log.Printf("fcm: failed to initialize Messaging client: %v", err)
		return &Client{}
	}
	return &Client{messaging: msgClient}
}

// Enabled reports whether a service account was configured and accepted.
func (c *Client) Enabled() bool {
	return c != nil && c.messaging != nil
}

// Send delivers a single push notification to one device token. data is
// attached as the FCM message's custom data payload (e.g.
// {"target_entity": "order_request", "target_id": "..."}) so the app can
// deep-link on tap — see api_client.dart/notifications handling on the
// Flutter side.
func (c *Client) Send(ctx context.Context, token, title, body string, data map[string]string) error {
	_, err := c.messaging.Send(ctx, &messaging.Message{
		Token: token,
		Notification: &messaging.Notification{
			Title: title,
			Body:  body,
		},
		Data: data,
		Android: &messaging.AndroidConfig{
			Priority: "high",
		},
	})
	return err
}

// IsUnregistered reports whether err indicates the token is no longer
// valid (app uninstalled, token rotated) — the caller should delete such
// tokens rather than retry them.
func IsUnregistered(err error) bool {
	return messaging.IsRegistrationTokenNotRegistered(err)
}
