package handlers

import (
	"strings"
	"testing"
)

// The single most important property: a limit nobody has set must not
// block anything. Every kyc_tier_limits row ships with all three columns
// NULL, and if that read as "cap of zero" the fork would take the whole
// platform offline the moment it deployed.
func TestUnsetLimitsBlockNothing(t *testing.T) {
	huge := int64(99_999_999_00)
	for _, tier := range []int16{0, 1, 2} {
		usage := volumeUsage{TodayPesewas: huge, CumulativePesewas: huge}
		if msg := checkTierLimit(tier, tierLimit{}, usage, huge); msg != "" {
			t.Errorf("tier %d with no limits set blocked a payment: %s", tier, msg)
		}
	}
}

func TestCheckTierLimit(t *testing.T) {
	// ₵500 per payment, ₵2,000 a day, ₵50,000 lifetime.
	limits := tierLimit{
		PerTransactionPesewas: 500_00,
		DailyPesewas:          2_000_00,
		CumulativePesewas:     50_000_00,
	}

	cases := []struct {
		name     string
		usage    volumeUsage
		amount   int64
		blocked  bool
		mentions string
	}{
		{
			name:   "comfortably inside every limit",
			usage:  volumeUsage{TodayPesewas: 100_00, CumulativePesewas: 5_000_00},
			amount: 200_00,
		},
		{
			name:   "exactly on the per-payment limit is allowed",
			usage:  volumeUsage{},
			amount: 500_00,
		},
		{
			name:     "one pesewa over the per-payment limit",
			usage:    volumeUsage{},
			amount:   500_01,
			blocked:  true,
			mentions: "single-payment",
		},
		{
			name:   "exactly filling the daily limit is allowed",
			usage:  volumeUsage{TodayPesewas: 1_500_00},
			amount: 500_00,
		},
		{
			name:     "one pesewa past the daily limit",
			usage:    volumeUsage{TodayPesewas: 1_500_01},
			amount:   500_00,
			blocked:  true,
			mentions: "daily limit",
		},
		{
			name:     "under both other caps but past the lifetime one",
			usage:    volumeUsage{TodayPesewas: 0, CumulativePesewas: 49_900_00},
			amount:   200_00,
			blocked:  true,
			mentions: "lifetime limit",
		},
		{
			name:   "a zero-amount check is never a violation",
			usage:  volumeUsage{TodayPesewas: 2_000_00, CumulativePesewas: 50_000_00},
			amount: 0,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			msg := checkTierLimit(1, limits, tc.usage, tc.amount)
			if tc.blocked && msg == "" {
				t.Fatalf("expected the payment to be blocked, it was allowed")
			}
			if !tc.blocked && msg != "" {
				t.Fatalf("expected the payment to be allowed, got: %s", msg)
			}
			if tc.mentions != "" && !strings.Contains(msg, tc.mentions) {
				t.Errorf("message should name which limit was hit (%q), got: %s", tc.mentions, msg)
			}
		})
	}
}

// A single cap set on its own must work without the other two — the Back
// Office lets a reviewer set exactly one.
func TestEachLimitWorksAlone(t *testing.T) {
	usage := volumeUsage{TodayPesewas: 900_00, CumulativePesewas: 9_000_00}

	if msg := checkTierLimit(1, tierLimit{PerTransactionPesewas: 100_00}, usage, 200_00); msg == "" {
		t.Error("per-transaction limit alone did not block an over-limit payment")
	}
	if msg := checkTierLimit(1, tierLimit{DailyPesewas: 1_000_00}, usage, 200_00); msg == "" {
		t.Error("daily limit alone did not block a payment past the day's cap")
	}
	if msg := checkTierLimit(1, tierLimit{CumulativePesewas: 9_100_00}, usage, 200_00); msg == "" {
		t.Error("cumulative limit alone did not block a payment past the lifetime cap")
	}
}

// A merchant already past a cap has no headroom — never negative headroom.
func TestRemainingNeverGoesNegative(t *testing.T) {
	if got := remaining(1_000_00, 1_500_00); got != 0 {
		t.Errorf("remaining(1000, 1500) = %d, want 0", got)
	}
	if got := remaining(1_000_00, 400_00); got != 600_00 {
		t.Errorf("remaining(1000, 400) = %d, want 60000", got)
	}

	over := volumeUsage{TodayPesewas: 5_000_00}
	msg := checkTierLimit(1, tierLimit{DailyPesewas: 1_000_00}, over, 100)
	if !strings.Contains(msg, "GH₵0.00 of today's limit is left") {
		t.Errorf("an over-limit merchant should be told nothing is left, got: %s", msg)
	}
}

// Every blocked message has to end in something the merchant can act on,
// and the action differs by tier — Tier 2 has no higher tier to reach.
func TestEveryTierGetsAnActionableNextStep(t *testing.T) {
	limits := tierLimit{PerTransactionPesewas: 100_00}
	for tier, want := range map[int16]string{
		0: "Ghana Card",
		1: "Register your business",
		2: "Contact support",
	} {
		msg := checkTierLimit(tier, limits, volumeUsage{}, 200_00)
		if !strings.Contains(msg, want) {
			t.Errorf("tier %d message should point at %q, got: %s", tier, want, msg)
		}
	}
}

func TestUpdateTierLimitRequestValidation(t *testing.T) {
	amount := func(v int64) *int64 { return &v }

	if err := (updateTierLimitRequest{}).validate(); err != nil {
		t.Errorf("clearing every limit should be valid, got: %v", err)
	}
	if err := (updateTierLimitRequest{PerTransactionPesewas: amount(0)}).validate(); err == nil {
		t.Error("a zero limit should be rejected — null is how a limit is cleared")
	}
	if err := (updateTierLimitRequest{PerTransactionPesewas: amount(-1)}).validate(); err == nil {
		t.Error("a negative limit should be rejected")
	}
	// An unreachable limit is a configuration error, not a stricter rule:
	// a ₵500 per-payment cap under a ₵100 daily cap can never be hit.
	if err := (updateTierLimitRequest{
		PerTransactionPesewas: amount(500_00),
		DailyPesewas:          amount(100_00),
	}).validate(); err == nil {
		t.Error("a per-payment limit above the daily limit should be rejected")
	}
	if err := (updateTierLimitRequest{
		DailyPesewas:      amount(500_00),
		CumulativePesewas: amount(100_00),
	}).validate(); err == nil {
		t.Error("a daily limit above the lifetime limit should be rejected")
	}
	if err := (updateTierLimitRequest{
		PerTransactionPesewas: amount(500_00),
		DailyPesewas:          amount(2_000_00),
		CumulativePesewas:     amount(50_000_00),
	}).validate(); err != nil {
		t.Errorf("a well-ordered set of limits should be valid, got: %v", err)
	}
}
