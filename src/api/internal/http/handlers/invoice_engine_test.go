package handlers

import (
	"testing"

	"github.com/jackc/pgx/v5/pgtype"
)

// pspFeeBps models Paystack Ghana's 1.95% collection fee. The real figure
// comes back per-charge from the PSP and is stored on payments.psp_fee_pesewas
// — this constant exists only so the margin assertions below can show the
// platform is actually left with something after the PSP takes its cut.
const pspFeeBps = 195

func pspFee(total int64) int64 { return total * pspFeeBps / 10000 }

func splitOf(bps int32) pgtype.Int4 { return pgtype.Int4{Int32: bps, Valid: true} }

func TestComputeInvoiceAmounts(t *testing.T) {
	tests := []struct {
		name          string
		subtotal      int64
		commissionBps int32
		allocation    string
		splitBps      pgtype.Int4
		deliveryFee   int64
		bundled       bool

		wantTotal      int64
		wantCommission int64
		wantService    int64
		// wantMerchantNet is total - commission: what ComputeSettlementAggregate
		// pays out to the merchant for this invoice.
		wantMerchantNet int64
	}{
		{
			name:          "customer pays the fee: merchant receives exactly the asking price",
			subtotal:      10000, // GHS 100.00
			commissionBps: 250,   // 2.50%
			allocation:    "customer_only",
			// GHS 100 / (1 - 0.025) = GHS 102.56, not GHS 102.50: the gross-up
			// covers the PSP taking its cut of the larger total.
			wantTotal:       10256,
			wantCommission:  256,
			wantService:     256,
			wantMerchantNet: 10000,
		},
		{
			name:            "merchant absorbs the fee: customer pays the sticker price",
			subtotal:        10000,
			commissionBps:   250,
			allocation:      "merchant_only",
			wantTotal:       10000,
			wantCommission:  250,
			wantService:     0,
			wantMerchantNet: 9750,
		},
		{
			name:            "split 50/50: customer covers half the commission",
			subtotal:        10000,
			commissionBps:   250,
			allocation:      "split",
			splitBps:        splitOf(5000),
			wantTotal:       10127,
			wantCommission:  253,
			wantService:     127,
			wantMerchantNet: 9874,
		},
		{
			// The regression this file exists for. Commissioning the subtotal
			// alone meant OrderxPay paid a PSP fee on the delivery portion and
			// earned nothing back on it: this invoice used to settle at a loss.
			name:            "bundled delivery is part of the commission base",
			subtotal:        2000, // GHS 20.00 of goods
			commissionBps:   250,
			allocation:      "customer_only",
			deliveryFee:     5000, // GHS 50.00 of delivery
			bundled:         true,
			wantTotal:       7179,
			wantCommission:  179,
			wantService:     179,
			wantMerchantNet: 7000,
		},
		{
			name:            "external delivery is settled off-invoice and is not commissioned",
			subtotal:        10000,
			commissionBps:   250,
			allocation:      "customer_only",
			deliveryFee:     5000,
			bundled:         false,
			wantTotal:       10256,
			wantCommission:  256,
			wantService:     256,
			wantMerchantNet: 10000,
		},
		{
			name:            "split with no split_bps set falls back to the merchant absorbing it",
			subtotal:        10000,
			commissionBps:   250,
			allocation:      "split",
			wantTotal:       10000,
			wantCommission:  250,
			wantService:     0,
			wantMerchantNet: 9750,
		},
		{
			name:            "unrecognised allocation never surprises the customer with a charge",
			subtotal:        10000,
			commissionBps:   250,
			allocation:      "something_new",
			wantTotal:       10000,
			wantCommission:  250,
			wantService:     0,
			wantMerchantNet: 9750,
		},
		{
			name:          "zero-value invoice",
			subtotal:      0,
			commissionBps: 250,
			allocation:    "customer_only",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := computeInvoiceAmounts(tc.subtotal, tc.commissionBps, tc.allocation, tc.splitBps, tc.deliveryFee, tc.bundled)

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

// TestPlatformMarginIsNeverNegative is the guard against the bug this
// calculation was rewritten to fix: whatever the mix of goods, delivery and
// allocation, the commission collected has to at least cover what the PSP
// charges on the same total.
func TestPlatformMarginIsNeverNegative(t *testing.T) {
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
		{1, 0},
		{250000, 3000},
	}

	for _, a := range allocations {
		for _, c := range cases {
			got := computeInvoiceAmounts(c.subtotal, 250, a.alloc, a.split, c.delivery, true)
			margin := got.CommissionPesewas - pspFee(got.TotalPesewas)
			if margin < 0 {
				t.Errorf("%s subtotal=%d delivery=%d: platform margin %d is negative (commission %d, psp fee %d, total %d)",
					a.name, c.subtotal, c.delivery, margin, got.CommissionPesewas, pspFee(got.TotalPesewas), got.TotalPesewas)
			}
		}
	}
}

// TestCustomerPaysFeeLeavesMerchantWhole checks the product promise behind
// the customer_only setting: the merchant banks their asking price, never
// less, whatever the amount.
func TestCustomerPaysFeeLeavesMerchantWhole(t *testing.T) {
	for _, base := range []int64{1, 99, 100, 999, 1000, 4567, 10000, 123456, 9999999} {
		got := computeInvoiceAmounts(base, 250, "customer_only", pgtype.Int4{}, 0, false)
		if net := got.TotalPesewas - got.CommissionPesewas; net < base {
			t.Errorf("base=%d: merchant nets %d, short of their asking price by %d", base, net, base-net)
		}
		if got.ServiceChargePesewas != got.TotalPesewas-base {
			t.Errorf("base=%d: disclosed service charge %d does not equal the amount added on top (%d)",
				base, got.ServiceChargePesewas, got.TotalPesewas-base)
		}
	}
}

// TestTotalAlwaysReconciles pins the invariant ComputeSettlementAggregate
// relies on: subtotal + service charge + bundled delivery == total.
func TestTotalAlwaysReconciles(t *testing.T) {
	for _, alloc := range []string{"customer_only", "merchant_only", "split"} {
		got := computeInvoiceAmounts(7500, 400, alloc, splitOf(3000), 2500, true)
		if sum := 7500 + got.ServiceChargePesewas + 2500; sum != got.TotalPesewas {
			t.Errorf("%s: subtotal+service+delivery = %d, but total = %d", alloc, sum, got.TotalPesewas)
		}
	}
}
