package handlers

import (
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

func revRow(name string, gmv, pspFee, commission, payments int64) db.GetMerchantRevenueBreakdownRow {
	return db.GetMerchantRevenueBreakdownRow{
		MerchantID:        pgtype.UUID{Bytes: uuid.New(), Valid: true},
		BusinessName:      name,
		MerchantStatus:    "active",
		GmvPesewas:        gmv,
		PspFeesPesewas:    pspFee,
		CommissionPesewas: commission,
		PaymentCount:      payments,
	}
}

func TestSummarizeReconciliation(t *testing.T) {
	rows := []db.GetMerchantRevenueBreakdownRow{
		// Healthy: booked ~2.5%, PSP took ~1.95%, margin positive.
		revRow("Ama Fabrics", 100_000, 1_950, 2_500, 8),
		// The delivery-leak shape: big GMV, but commission was booked on the
		// goods subtotal only while the PSP charged 1.95% of the whole
		// (delivery-inflated) total. Realized margin is negative.
		revRow("Kofi Logistics", 200_000, 3_900, 500, 5),
		// Dormant this period — must be dropped, not carried as a zero row.
		revRow("Silent Trader", 0, 0, 0, 0),
	}

	summary, merchants := summarizeReconciliation(rows, 195, 3)

	if len(merchants) != 2 {
		t.Fatalf("expected 2 active merchants, got %d", len(merchants))
	}

	// Worst margin first.
	if merchants[0].BusinessName != "Kofi Logistics" {
		t.Errorf("expected the underwater merchant sorted first, got %q", merchants[0].BusinessName)
	}
	if merchants[0].RealizedMarginPesewas != 500-3_900 {
		t.Errorf("Kofi realized margin = %d, want %d", merchants[0].RealizedMarginPesewas, 500-3_900)
	}
	if merchants[1].RealizedMarginPesewas != 2_500-1_950 {
		t.Errorf("Ama realized margin = %d, want %d", merchants[1].RealizedMarginPesewas, 2_500-1_950)
	}

	// Effective take rate: 2_500 / 100_000 = 250 bps for Ama.
	if merchants[1].EffectiveTakeRateBps != 250 {
		t.Errorf("Ama effective take rate = %d bps, want 250", merchants[1].EffectiveTakeRateBps)
	}

	if summary.GMVPesewas != 300_000 {
		t.Errorf("summary GMV = %d, want 300000", summary.GMVPesewas)
	}
	if summary.BookedCommissionPesewas != 3_000 {
		t.Errorf("summary booked commission = %d, want 3000", summary.BookedCommissionPesewas)
	}
	if summary.PSPFeeActualPesewas != 5_850 {
		t.Errorf("summary actual PSP fee = %d, want 5850", summary.PSPFeeActualPesewas)
	}
	// Expected: 300_000 * 195 / 10000 = 5_850. Here actual == expected, so
	// no model drift — the leak shows up as a booking shortfall, not as the
	// PSP charging more than the model assumes.
	if summary.PSPFeeExpectedPesewas != 5_850 {
		t.Errorf("summary expected PSP fee = %d, want 5850", summary.PSPFeeExpectedPesewas)
	}
	if summary.PSPFeeDriftPesewas != 0 {
		t.Errorf("summary PSP drift = %d, want 0", summary.PSPFeeDriftPesewas)
	}
	// Realized margin = 3_000 booked - 5_850 paid to the PSP = -2_850.
	if summary.RealizedMarginPesewas != -2_850 {
		t.Errorf("summary realized margin = %d, want -2850", summary.RealizedMarginPesewas)
	}
	if summary.RealizedMarginBps != -2_850*10000/300_000 {
		t.Errorf("summary realized margin bps = %d, want %d", summary.RealizedMarginBps, -2_850*10000/300_000)
	}
	if summary.UnderwaterMerchantCount != 1 {
		t.Errorf("underwater merchant count = %d, want 1", summary.UnderwaterMerchantCount)
	}
	if summary.UnderwaterPaymentCount != 3 {
		t.Errorf("underwater payment count = %d, want 3 (passed through from the query)", summary.UnderwaterPaymentCount)
	}
	if summary.ExpectedCollectionFeeBps != 195 {
		t.Errorf("expected collection fee bps = %d, want 195", summary.ExpectedCollectionFeeBps)
	}
}

// When the PSP charges more than the pass-through component of the model
// assumes, that surfaces as positive drift — the automatic "the next
// pricing drift" alarm the brief wants.
func TestSummarizeReconciliationSurfacesPSPDrift(t *testing.T) {
	rows := []db.GetMerchantRevenueBreakdownRow{
		// PSP actually took 2.30% (2_300 on 100_000) vs. the 1.95% the model
		// assumes.
		revRow("Yaa Foods", 100_000, 2_300, 2_500, 4),
	}

	summary, _ := summarizeReconciliation(rows, 195, 0)

	if summary.PSPFeeExpectedPesewas != 1_950 {
		t.Fatalf("expected PSP fee = %d, want 1950", summary.PSPFeeExpectedPesewas)
	}
	if summary.PSPFeeDriftPesewas != 350 {
		t.Errorf("PSP drift = %d, want 350 (actual 2300 - expected 1950)", summary.PSPFeeDriftPesewas)
	}
	// Still net positive here — 2_500 booked - 2_300 paid — so nobody is
	// flagged underwater even though the drift is real.
	if summary.UnderwaterMerchantCount != 0 {
		t.Errorf("underwater merchant count = %d, want 0", summary.UnderwaterMerchantCount)
	}
	if summary.RealizedMarginPesewas != 200 {
		t.Errorf("realized margin = %d, want 200", summary.RealizedMarginPesewas)
	}
}

func TestSummarizeReconciliationEmptyPeriod(t *testing.T) {
	summary, merchants := summarizeReconciliation(nil, 195, 0)
	if len(merchants) != 0 {
		t.Errorf("expected no merchants, got %d", len(merchants))
	}
	if summary.RealizedMarginBps != 0 || summary.PSPFeeExpectedPesewas != 0 {
		t.Errorf("empty period should be all zeros, got %+v", summary)
	}
}
