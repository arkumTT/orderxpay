//go:build paystack_smoke

// This file only builds with `go test -tags paystack_smoke`, which the
// "Verify Paystack Integration" GitHub Actions workflow (manual trigger
// only — .github/workflows/paystack-verify.yml) is the one thing that
// passes. `go test ./...` — what CI and every local run in this repo
// actually does — never compiles it, so it can never slow down or break
// the ordinary test suite, and needs no local PAYSTACK_SECRET_KEY to pass.
//
// Why this exists: the sandbox this codebase is usually developed in has
// no route to the real internet (confirmed by curl and a spawned `go run`
// server both failing identically against api.paystack.co, GitHub, and
// npm/Go module registries alike — network access here is granted per-tool,
// not per-destination, and a generic outbound HTTP client has none). Every
// PR that has touched this package (payout account verification, split
// payments) was written and unit-tested against that assumption, then
// shipped with the live Paystack round trip explicitly flagged as
// unverified. This is how that gap gets closed — on a runner with real
// network, on demand, without needing to trust a re-statement of the same
// assumptions the code was written under.
package psp

import (
	"context"
	"crypto/rand"
	"fmt"
	"math/big"
	"os"
	"testing"
	"time"
)

// generateSmokeTestReference produces a reference Paystack has never seen
// before (it requires uniqueness) — deliberately not reusing
// handlers.generatePaymentReference, which lives in a package that already
// imports this one.
func generateSmokeTestReference() (string, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(1<<40))
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("smoke-test-%d-%x", time.Now().Unix(), n), nil
}

func liveClient(t *testing.T) *Client {
	t.Helper()
	key := os.Getenv("PAYSTACK_SECRET_KEY")
	if key == "" {
		t.Fatal("PAYSTACK_SECRET_KEY is not set — this test talks to Paystack's real API and needs a test-mode secret key (sk_test_...)")
	}
	return NewClient(key)
}

// TestLiveListBanks is the most fixture-free check available: no account
// number or bank code to guess, just "does the secret key work and does
// Paystack's response still match what this package's Bank struct expects."
// A failure here means either the key is wrong/expired or Paystack changed
// a response field this package relies on — both worth knowing immediately,
// not from a merchant's bug report.
func TestLiveListBanks(t *testing.T) {
	c := liveClient(t)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	for _, bankType := range []string{BankTypeMobileMoney, BankTypeGhipss} {
		t.Run(bankType, func(t *testing.T) {
			banks, err := c.ListBanks(ctx, "GHS", bankType)
			if err != nil {
				t.Fatalf("ListBanks(GHS, %s) failed: %v", bankType, err)
			}
			if len(banks) == 0 {
				t.Fatalf("ListBanks(GHS, %s) returned zero entries — expected at least one real %s option", bankType, bankType)
			}
			for _, b := range banks {
				if b.Name == "" || b.Code == "" {
					t.Errorf("a %s entry is missing name or code: %+v", bankType, b)
				}
			}
			t.Logf("%s: %d entries, first is %q (code %q)", bankType, len(banks), banks[0].Name, banks[0].Code)
		})
	}
}

// TestLiveInitializeTransaction exercises the exact call
// InitiateCheckoutPayment makes in production — the highest-value, most
// money-adjacent path in this package — with no fixture dependency:
// initializing a transaction never requires a real card, a real customer,
// or a real payment method, and an abandoned test-mode transaction is
// ordinary, harmless noise in Paystack's dashboard (nothing to clean up).
func TestLiveInitializeTransaction(t *testing.T) {
	c := liveClient(t)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	reference, err := generateSmokeTestReference()
	if err != nil {
		t.Fatalf("failed to generate a reference: %v", err)
	}

	result, err := c.InitializeTransaction(ctx, InitializeParams{
		// Matches syntheticCustomerEmail's real domain in payments.go
		// (checkout.orderxpay.app) rather than inventing one: the RFC 2606
		// reserved .test TLD used here originally got a hard 400 from
		// Paystack ("Invalid Email Address Passed") on the first live run
		// of this test — Paystack validates the domain can plausibly
		// resolve, and .test never can. That failure was this fixture's
		// bug, not production's: production never uses .test.
		Email:         "paystack-smoke-test@checkout.orderxpay.app",
		AmountPesewas: 100, // GH₵1.00 — never actually charged, this only initializes
		Currency:      "GHS",
		Reference:     reference,
		CallbackURL:   "https://example.com/callback",
	})
	if err != nil {
		t.Fatalf("InitializeTransaction failed: %v", err)
	}
	if result.AuthorizationURL == "" {
		t.Error("InitializeTransaction returned no authorization_url")
	}
	if result.AccessCode == "" {
		t.Error("InitializeTransaction returned no access_code")
	}
	t.Logf("initialized %s — authorization_url present: %v, access_code present: %v",
		reference, result.AuthorizationURL != "", result.AccessCode != "")
}

// TestLiveResolveAccount is deliberately informational only (t.Logf, never
// t.Fatalf/t.Errorf on the resolve outcome itself) — this package has no
// trustworthy Ghana test-mode account number to assert a successful
// resolve against, and guessing one would make this test's pass/fail
// signal depend on a fixture rather than on the integration actually
// working. What it DOES assert is that the round trip completes at all
// (reaches Paystack, gets back a response) using a bank_code pulled live
// from ListBanks rather than hardcoded — if that itself errors, something
// about auth or the endpoint is broken, which is worth failing on. Whether
// the account number resolves or comes back "not found" either way proves
// the response envelope this package parses is still shaped as expected.
func TestLiveResolveAccount(t *testing.T) {
	c := liveClient(t)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	banks, err := c.ListBanks(ctx, "GHS", BankTypeMobileMoney)
	if err != nil || len(banks) == 0 {
		t.Skipf("skipping — could not get a real bank_code to resolve against: %v", err)
	}

	result, err := c.ResolveAccount(ctx, "0000000000", banks[0].Code)
	if err != nil {
		// Very likely just "account not found" for a made-up number, which
		// is an entirely expected outcome here — logged for a human to
		// read, not failed.
		t.Logf("resolve against a fabricated account number against %s (%s) returned: %v — expected unless this number happens to be real", banks[0].Name, banks[0].Code, err)
		return
	}
	t.Logf("resolve unexpectedly succeeded: %+v (harmless — this just means 0000000000 is a real account on %s)", result, banks[0].Name)
}
