// Package email sends mail over plain SMTP — deliberately generic rather
// than tied to one vendor's API, per the scoping decision for this
// integration (feedback: "generic SMTP, works with any provider you
// already have"). Works with Gmail, Zoho, or any transactional-email
// provider's SMTP relay (SendGrid, Mailgun, Postmark, AWS SES all expose
// one) — whatever host/port/username/password the merchant's operator
// already has. Unlike sms.Client and whatsapp.Client, this is
// env-configured only: SMTP needs five separate values (host, port,
// username, password, from-address), not a single rotatable secret
// string, so it doesn't fit the Integrations page's one-secret-per-
// provider model the way Paystack/WhatsApp/SMS do. Rotate it by editing
// the server's environment and restarting, same as DATABASE_URL.
package email

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"net"
	"net/smtp"
	"strings"
)

type Client struct {
	Host      string
	Port      string
	Username  string
	Password  string
	FromEmail string
	FromName  string
}

func NewClient(host, port, username, password, fromEmail, fromName string) *Client {
	return &Client{
		Host:      host,
		Port:      port,
		Username:  username,
		Password:  password,
		FromEmail: fromEmail,
		FromName:  fromName,
	}
}

// Enabled reports whether SMTP has been configured. Callers should skip
// sending (not error loudly) when false, the same graceful-degrade
// posture as sms.Client.Enabled() and whatsapp.Client.Enabled().
func (c *Client) Enabled() bool {
	return c != nil && c.Host != "" && c.Port != "" && c.FromEmail != ""
}

// Send delivers a plain-text email. ctx is accepted for interface
// consistency with the other client packages, but net/smtp itself has no
// context-aware dial/send path — a slow or hanging SMTP server isn't
// cancellable mid-send the way the HTTP-based sms/whatsapp clients are.
func (c *Client) Send(ctx context.Context, to, subject, body string) error {
	if !c.Enabled() {
		return errors.New("email: smtp not configured")
	}
	if to == "" {
		return errors.New("email: recipient is required")
	}

	from := c.FromEmail
	if c.FromName != "" {
		from = fmt.Sprintf("%s <%s>", c.FromName, c.FromEmail)
	}
	msg := []byte(strings.Join([]string{
		"From: " + from,
		"To: " + to,
		"Subject: " + subject,
		"MIME-Version: 1.0",
		"Content-Type: text/plain; charset=\"UTF-8\"",
		"",
		body,
	}, "\r\n"))

	addr := net.JoinHostPort(c.Host, c.Port)
	var auth smtp.Auth
	if c.Username != "" {
		auth = smtp.PlainAuth("", c.Username, c.Password, c.Host)
	}

	// Port 465 is implicit TLS from the first byte (no STARTTLS
	// negotiation) — smtp.SendMail can't do that, it only handles the
	// STARTTLS-after-plaintext-EHLO upgrade that 587/25 use. Handle 465
	// explicitly so a provider that only offers implicit TLS still works.
	if c.Port == "465" {
		return c.sendImplicitTLS(addr, auth, c.FromEmail, []string{to}, msg)
	}
	return smtp.SendMail(addr, auth, c.FromEmail, []string{to}, msg)
}

func (c *Client) sendImplicitTLS(addr string, auth smtp.Auth, from string, to []string, msg []byte) error {
	conn, err := tls.Dial("tcp", addr, &tls.Config{ServerName: c.Host})
	if err != nil {
		return fmt.Errorf("email: tls dial: %w", err)
	}
	defer conn.Close()

	client, err := smtp.NewClient(conn, c.Host)
	if err != nil {
		return fmt.Errorf("email: smtp client: %w", err)
	}
	defer client.Close()

	if auth != nil {
		if err := client.Auth(auth); err != nil {
			return fmt.Errorf("email: auth: %w", err)
		}
	}
	if err := client.Mail(from); err != nil {
		return fmt.Errorf("email: MAIL FROM: %w", err)
	}
	for _, addr := range to {
		if err := client.Rcpt(addr); err != nil {
			return fmt.Errorf("email: RCPT TO: %w", err)
		}
	}
	w, err := client.Data()
	if err != nil {
		return fmt.Errorf("email: DATA: %w", err)
	}
	if _, err := w.Write(msg); err != nil {
		return fmt.Errorf("email: write body: %w", err)
	}
	if err := w.Close(); err != nil {
		return fmt.Errorf("email: close body: %w", err)
	}
	return client.Quit()
}
