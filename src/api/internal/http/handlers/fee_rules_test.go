package handlers

import "testing"

func TestDeriveMerchantSetMarginBps(t *testing.T) {
	const collectionFeeBps = 195 // today's real Paystack pass-through

	cases := []struct {
		name          string
		requestedBps  int32
		wantMarginBps int32
		wantErr       bool
	}{
		{
			name:          "at the platform default (2.5%) — same as today's global rate",
			requestedBps:  250,
			wantMarginBps: 55,
		},
		{
			name:          "exactly at the collection fee — zero margin, allowed",
			requestedBps:  195,
			wantMarginBps: 0,
		},
		{
			name:          "exactly at the 5% cap — allowed",
			requestedBps:  500,
			wantMarginBps: 305,
		},
		{
			name:         "one bps over the 5% cap — rejected",
			requestedBps: 501,
			wantErr:      true,
		},
		{
			name:         "an outsized 20% \"service charge\" — the exact abuse case the brief names",
			requestedBps: 2000,
			wantErr:      true,
		},
		{
			name:         "one bps below the collection fee — would imply negative margin, rejected",
			requestedBps: 194,
			wantErr:      true,
		},
		{
			name:         "negative — rejected before it ever reaches the collection-fee floor",
			requestedBps: -1,
			wantErr:      true,
		},
		{
			name:          "zero — rejected only if the collection fee itself is positive",
			requestedBps:  0,
			wantMarginBps: 0,
			wantErr:       true, // 0 < 195, so this hits the collection-fee floor
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := deriveMerchantSetMarginBps(tc.requestedBps, collectionFeeBps)
			if tc.wantErr {
				if err == nil {
					t.Fatalf("expected an error, got margin %d", got)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got != tc.wantMarginBps {
				t.Errorf("deriveMerchantSetMarginBps(%d, %d) = %d, want %d", tc.requestedBps, collectionFeeBps, got, tc.wantMarginBps)
			}
		})
	}
}

// The cap is on the TOTAL commission a merchant can set, not on margin
// alone — so a merchant whose collection fee is unusually high (a costlier
// payment method, say) gets correspondingly less room to add their own
// margin before hitting 5%, never more.
func TestMerchantSetRateCapAppliesToTotalNotJustMargin(t *testing.T) {
	// 450 collection leaves exactly 50 bps of margin headroom under a 500
	// cap — asking for that boundary total should succeed with no margin
	// left to spare.
	got, err := deriveMerchantSetMarginBps(500, 450)
	if err != nil || got != 50 {
		t.Fatalf("deriveMerchantSetMarginBps(500, 450) = (%d, %v), want (50, nil)", got, err)
	}

	// If the collection fee alone already exceeds the cap, no total is
	// reachable — even asking for zero margin (total == collection fee)
	// must be rejected, not silently allowed because margin is technically
	// zero.
	if _, err := deriveMerchantSetMarginBps(600, 600); err == nil {
		t.Error("a 600 bps collection fee alone already exceeds the 500 bps cap — should be rejected even at zero margin")
	}
}

func TestMerchantSetRateCapIsFiveHundredBps(t *testing.T) {
	if merchantSetRateCapBps != 500 {
		t.Errorf("merchantSetRateCapBps = %d, want 500 (5.00%%) per the fee-architecture brief", merchantSetRateCapBps)
	}
}
