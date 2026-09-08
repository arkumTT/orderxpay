package handlers

import (
	"testing"

	"github.com/jackc/pgx/v5/pgtype"
)

// The recommended model: 1.95% passed through to the PSP, 0.55% kept,
// floored at GHS 0.20 and capped at GHS 25.00 per invoice.
var standardPricing = pricing{
	CollectionFeeBps: 195,
	MarginBps:        55,
	MarginFloor:      20,
	MarginCap:        2500,
}

// pspCost is what the PSP takes out of a given total. The real figure comes
// back per-charge and is stored on payments.psp_fee_pesewas; this mirrors
// the pass-through component so the assertions below can show what OrderxPay
// is actually left holding.
func pspCost(total int64) int64 { return total * 195 / 10000 }

func splitOf(bps int32) pgtype.Int4 { return pgtype.Int4{Int32: bps, Valid: true} }

func TestComputeInvoiceAmounts(t *testing.T) {
	tests := []struct {
		name        string
		subtotal    int64
		allocation  string
		splitBps    pgtype.Int4
		deliveryFee int64
		bundled     bool

		wantTotal      int64
		wantCommission int64
		wantService    int64
		// wantMerchantNet is total - commission: what the settlement engine
		// pays out to the merchant for this invoice.
		wantMerchantNet int64
	}{
		{
			// GHS 100 / (1 - 0.025) = GHS 102.56, not GHS 102.50: the gross-up
			// covers the PSP taking its cut of the larger total.
			name:            "customer pays the fee: merchant is left whole",
			subtotal:        10000,
			allocation:      "customer_only",
			wantTotal:       10256,
			wantCommission:  255,
			wantService:     256,
			wantMerchantNet: 10001,
		},
		{
			name:            "merchant absorbs the fee: customer pays the sticker price",
			subtotal:        10000,
			allocation:      "merchant_only",
			wantTotal:       10000,
			wantCommission:  250,
			wantService:     0,
			wantMerchantNet: 9750,
		},
		{
			name:            "split 50/50: customer covers half the commission",
			subtotal:        10000,
			allocation:      "split",
			splitBps:        splitOf(5000),
			wantTotal:       10127,
			wantCommission:  252,
			wantService:     127,
			wantMerchantNet: 9875,
		},
		{
			// The regression this file exists for. Commissioning the subtotal
			// alone meant OrderxPay paid a PSP fee on the delivery portion and
			// earned nothing back on it: this invoice used to settle at a loss.
			name:            "bundled delivery is part of the commission base",
			subtotal:        2000, // GHS 20.00 of goods
			allocation:      "customer_only",
			deliveryFee:     5000, // GHS 50.00 of delivery
			bundled:         true,
			wantTotal:       7179,
			wantCommission:  178,
			wantService:     179,
			wantMerchantNet: 7001,
		},
		{
			name:            "external delivery is settled off-invoice and is not commissioned",
			subtotal:        10000,
			allocation:      "customer_only",
			deliveryFee:     5000,
			wantTotal:       10256,
			wantCommission:  255,
			wantService:     256,
			wantMerchantNet: 10001,
		},
		{
			// 0.55% of GHS 5.00 is under a pesewa, which is not worth carrying:
			// the floor lifts OrderxPay's margin to GHS 0.20 and the customer
			// pays GHS 0.30 all in.
			name:            "small invoice: the margin floor applies",
			subtotal:        500,
			allocation:      "customer_only",
			wantTotal:       530,
			wantCommission:  30,
			wantService:     30,
			wantMerchantNet: 500,
		},
		{
			name:            "split with no split_bps set falls back to the merchant absorbing it",
			subtotal:        10000,
			allocation:      "split",
			wantTotal:       10000,
			wantCommission:  250,
			wantService:     0,
			wantMerchantNet: 9750,
		},
		{
			name:            "unrecognised allocation never surprises the customer with a charge",
			subtotal:        10000,
			allocation:      "something_new",
			wantTotal:       10000,
			wantCommission:  250,
			wantService:     0,
			wantMerchantNet: 9750,
		},
		{
			// A zero-value invoice is not a chargeable event, so the margin
			// floor must not conjure a fee out of it.
			name:       "zero-value invoice",
			subtotal:   0,
			allocation: "customer_only",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := computeInvoiceAmounts(tc.subtotal, standardPricing, tc.allocation, tc.splitBps, tc.deliveryFee, tc.bundled)

			if got.TotalPesewas != tc.wantTotal {
				t.Errorf("total = %d, want %d", got.TotalPesewas, tc.wantTotal)
			}
			if got.CommissionPesewas != tc.wantCommission {
				t.Errorf("commission = %d, want %d", got.CommissionPesewas, tc.wantCommission)
			}
			if got.ServiceChargePesewas != tc.wantService {
				t.Errorf("service charge = %d, want %d", got.ServiceChargePesewas, tc.wantService)
			}
			if net := got.TotalPesewas - got.CommissionPesewas; net != tc.wantMerchantNet {
				t.Errorf("merchant net = %d, want %d", net, tc.wantMerchantNet)
			}
		})
	}
}

// TestMarginCapHoldsDownLargeInvoices checks the acceptance half of the
// model: past the cap the effective rate falls away from the headline rate,
// which is what keeps a large invoice from being taken off-platform.
func TestMarginCapHoldsDownLargeInvoices(t *testing.T) {
	// GHS 8,000 — well past where 0.55% exceeds the GHS 25 cap.
	got := computeInvoiceAmounts(800000, standardPricing, "customer_only", pgtype.Int4{}, 0, false)

	margin := got.CommissionPesewas - pspCost(got.TotalPesewas)
	if margin != standardPricing.MarginCap {
		t.Errorf("margin = %d, want it pinned to the cap of %d", margin, standardPricing.MarginCap)
	}

	// Effective rate has to sit below the headline 2.5% but still above the
	// 1.95% the transaction costs.
	effectiveBps := got.ServiceChargePesewas * 10000 / 800000
	if effectiveBps >= 250 {
		t.Errorf("effective rate %d bps did not fall below the uncapped 250 bps", effectiveBps)
	}
	if effectiveBps <= 195 {
		t.Errorf("effective rate %d bps fell to or below the PSP cost of 195 bps", effectiveBps)
	}
}

// TestPlatformNeverLosesMoney is the guard against the bug this calculation
// was rewritten to fix, extended to the clamps: whatever the mix of goods,
// delivery, allocation and ticket size, the commission collected has to
// cover what the PSP charges on the same total.
func TestPlatformNeverLosesMoney(t *testing.T) {
	allocations := []struct {
		name  string
		alloc string
		split pgtype.Int4
	}{
		{"customer_only", "customer_only", pgtype.Int4{}},
		{"merchant_only", "merchant_only", pgtype.Int4{}},
		{"split_50", "split", splitOf(5000)},
		{"split_10", "split", splitOf(1000)},
	}

	// Deliberately lopsided pairs: a small order carrying a large delivery
	// fee is exactly the shape that used to lose money.
	cases := []struct{ subtotal, delivery int64 }{
		{2000, 5000},
		{500, 5000},
		{100, 10000},
		{10000, 0},
		{100, 0},
		{250000, 3000},
		{5000000, 0},
	}

	for _, a := range allocations {
		for _, c := range cases {
			got := computeInvoiceAmounts(c.subtotal, standardPricing, a.alloc, a.split, c.delivery, true)
			base := c.subtotal + c.delivery

			margin := got.CommissionPesewas - pspCost(got.TotalPesewas)
			if margin < 0 {
				t.Errorf("%s subtotal=%d delivery=%d: margin %d is negative (commission %d, psp %d, total %d)",
					a.name, c.subtotal, c.delivery, margin, got.CommissionPesewas, pspCost(got.TotalPesewas), got.TotalPesewas)
			}
			if margin > standardPricing.MarginCap {
				t.Errorf("%s subtotal=%d delivery=%d: margin %d exceeded the cap %d",
					a.name, c.subtotal, c.delivery, margin, standardPricing.MarginCap)
			}
			if margin < standardPricing.MarginFloor {
				t.Errorf("%s subtotal=%d delivery=%d: margin %d fell under the floor %d",
					a.name, c.subtotal, c.delivery, margin, standardPricing.MarginFloor)
			}
			if got.CommissionPesewas > got.TotalPesewas {
				t.Errorf("%s subtotal=%d delivery=%d: commission %d exceeds the total collected %d",
					a.name, c.subtotal, c.delivery, got.CommissionPesewas, got.TotalPesewas)
			}
			// Reconciliation identity ComputeSettlementAggregate depends on.
			if sum := base + got.ServiceChargePesewas; sum != got.TotalPesewas {
				t.Errorf("%s subtotal=%d delivery=%d: base+service = %d but total = %d",
					a.name, c.subtotal, c.delivery, sum, got.TotalPesewas)
			}
		}
	}
}

// TestCustomerPaysFeeLeavesMerchantWhole checks the product promise behind
// the customer_only setting: the merchant banks their asking price, never
// less, at every size including across both clamps.
func TestCustomerPaysFeeLeavesMerchantWhole(t *testing.T) {
	for _, base := range []int64{100, 500, 999, 1000, 4567, 10000, 123456, 800000, 9999999} {
		got := computeInvoiceAmounts(base, standardPricing, "customer_only", pgtype.Int4{}, 0, false)
		if net := got.TotalPesewas - got.CommissionPesewas; net < base {
			t.Errorf("base=%d: merchant nets %d, short of their asking price by %d", base, net, base-net)
		}
	}
}

func TestWithdrawalFee(t *testing.T) {
	const momo, bank, waiver = 100, 800, 50000 // GHS 1, GHS 8, waived at GHS 500

	momoAccount := pgtype.Text{String: "momo", Valid: true}
	bankAccount := pgtype.Text{String: "bank", Valid: true}
	noAccount := pgtype.Text{}

	tests := []struct {
		name    string
		account pgtype.Text
		payout  int64
		want    int64
	}{
		{"mobile money under the waiver", momoAccount, 20000, 100},
		{"bank under the waiver", bankAccount, 20000, 800},
		{"waived once the payout is worth taking", momoAccount, 50000, 0},
		{"waived well past the threshold", bankAccount, 500000, 0},
		// Payout account capture ships separately; until it does, an unset
		// account is priced as mobile money — the cheaper of the two, so it
		// can never overcharge.
		{"no payout account yet is priced as mobile money", noAccount, 20000, 100},
		// A fee larger than the payout would hand back a negative amount.
		{"fee never exceeds the payout it is charged on", bankAccount, 300, 300},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := withdrawalFee(momo, bank, waiver, tc.account, tc.payout); got != tc.want {
				t.Errorf("withdrawalFee = %d, want %d", got, tc.want)
			}
		})
	}
}
