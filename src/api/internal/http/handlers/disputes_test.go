package handlers

import (
	"testing"

	"github.com/jackc/pgx/v5/pgtype"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

func TestMerchantEntitledShare(t *testing.T) {
	cases := []struct {
		name       string
		refund     int64
		total      int64
		commission int64
		want       int64
	}{
		{
			name:       "full refund on an invoice with no commission overrides",
			refund:     10_000,
			total:      10_000,
			commission: 250,
			want:       9_750, // the merchant's whole entitled share comes back
		},
		{
			name:       "partial refund — same 97.5% ratio applies to just the slice refunded",
			refund:     4_000,
			total:      10_000,
			commission: 250,
			want:       3_900, // 4000 * 9750/10000
		},
		{
			name:       "customer absorbed the whole fee — merchant's entitlement is effectively the full invoice",
			refund:     10_256,
			total:      10_256,
			commission: 256,
			want:       10_000,
		},
		{
			name:       "zero-total invoice guards the division rather than panicking",
			refund:     500,
			total:      0,
			commission: 0,
			want:       0,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := merchantEntitledShare(tc.refund, tc.total, tc.commission)
			if got != tc.want {
				t.Errorf("merchantEntitledShare(%d, %d, %d) = %d, want %d", tc.refund, tc.total, tc.commission, got, tc.want)
			}
		})
	}
}

// The clawback recovers what the merchant was paid, not what the customer
// gets back — OrderxPay's own commission on the refunded slice was never
// paid out in the first place, so it's not part of the debt.
func TestMerchantEntitledShareExcludesCommission(t *testing.T) {
	refund := int64(1_000)
	total := int64(10_000)
	commission := int64(500) // 5% commission on this invoice
	got := merchantEntitledShare(refund, total, commission)
	want := int64(950) // 1000 * 9500/10000 — 5% of the refund stays OrderxPay's, never the merchant's
	if got != want {
		t.Errorf("merchantEntitledShare(%d, %d, %d) = %d, want %d", refund, total, commission, got, want)
	}
	if got == refund {
		t.Error("the merchant's entitled share should never equal the raw refund when commission is nonzero")
	}
}

func TestMerchantAlreadyReceivedPayout(t *testing.T) {
	valid := pgtype.UUID{Bytes: [16]byte{1}, Valid: true}
	validText := pgtype.Text{String: "SUB_abc123", Valid: true}

	cases := []struct {
		name string
		pmt  db.Payment
		want bool
	}{
		{
			name: "neither settled nor split — money is still sitting in OrderxPay's balance",
			pmt:  db.Payment{},
			want: false,
		},
		{
			name: "settled — a completed settlement already paid the merchant",
			pmt:  db.Payment{SettlementID: valid},
			want: true,
		},
		{
			name: "split — Paystack sent the merchant's share straight to their subaccount",
			pmt:  db.Payment{PaystackSubaccountCode: validText},
			want: true,
		},
		{
			name: "theoretically both set — still true, not double-counted by this bool",
			pmt:  db.Payment{SettlementID: valid, PaystackSubaccountCode: validText},
			want: true,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := merchantAlreadyReceivedPayout(tc.pmt); got != tc.want {
				t.Errorf("merchantAlreadyReceivedPayout(%+v) = %v, want %v", tc.pmt, got, tc.want)
			}
		})
	}
}

// The bug this locks in: a split payment's settlement_id is NULL forever
// (ComputeSettlementAggregate excludes split payments from every
// settlement it ever computes), so checking SettlementID alone silently
// misses every split-payment refund — exactly the gap the Fee Architecture
// brief named as needing an answer before split payments go live for
// anyone.
func TestMerchantAlreadyReceivedPayoutCatchesSplitPaymentsSettlementIDMisses(t *testing.T) {
	splitPayment := db.Payment{
		PaystackSubaccountCode: pgtype.Text{String: "SUB_abc123", Valid: true},
		// SettlementID deliberately left zero-value (invalid) — this is the
		// permanent state for a split payment, not a transient one.
	}
	if splitPayment.SettlementID.Valid {
		t.Fatal("test setup error: SettlementID should be invalid for this case")
	}
	if !merchantAlreadyReceivedPayout(splitPayment) {
		t.Error("a split payment's merchant share already left OrderxPay's balance even though settlement_id is NULL — merchantAlreadyReceivedPayout must catch this")
	}
}
