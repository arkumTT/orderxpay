package handlers

import "testing"

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
