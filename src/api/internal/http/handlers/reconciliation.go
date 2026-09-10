package handlers

import (
	"sort"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

// defaultCollectionFeeBps is the pass-through rate the pricing model assumes
// the PSP takes (Fee Architecture brief). Used as the expected-cost baseline
// only if the global fee rule can't be read.
const defaultCollectionFeeBps = 195

type reconciliationMerchant struct {
	MerchantID              string `json:"merchant_id"`
	BusinessName            string `json:"business_name"`
	GMVPesewas              int64  `json:"gmv_pesewas"`
	BookedCommissionPesewas int64  `json:"booked_commission_pesewas"`
	PSPFeePesewas           int64  `json:"psp_fee_pesewas"`
	RealizedMarginPesewas   int64  `json:"realized_margin_pesewas"` // booked commission - PSP fee
	EffectiveTakeRateBps    int64  `json:"effective_take_rate_bps"` // booked commission / GMV
	PaymentCount            int64  `json:"payment_count"`
}

type underwaterPayment struct {
	InvoiceReference        string `json:"invoice_reference"`
	MerchantID              string `json:"merchant_id"`
	BusinessName            string `json:"business_name"`
	AmountPesewas           int64  `json:"amount_pesewas"`
	BookedCommissionPesewas int64  `json:"booked_commission_pesewas"`
	PSPFeePesewas           int64  `json:"psp_fee_pesewas"`
	ShortfallPesewas        int64  `json:"shortfall_pesewas"` // PSP fee - booked commission, always > 0 here
	PaidAt                  string `json:"paid_at"`
}

type reconciliationSummary struct {
	GMVPesewas               int64 `json:"gmv_pesewas"`
	BookedCommissionPesewas  int64 `json:"booked_commission_pesewas"`
	PSPFeeActualPesewas      int64 `json:"psp_fee_actual_pesewas"`
	PSPFeeExpectedPesewas    int64 `json:"psp_fee_expected_pesewas"` // GMV * expected collection fee bps
	PSPFeeDriftPesewas       int64 `json:"psp_fee_drift_pesewas"`    // actual - expected; positive means the PSP took more than the model assumes
	RealizedMarginPesewas    int64 `json:"realized_margin_pesewas"`  // booked commission - actual PSP fee
	RealizedMarginBps        int64 `json:"realized_margin_bps"`      // realized margin / GMV
	ExpectedCollectionFeeBps int64 `json:"expected_collection_fee_bps"`
	UnderwaterMerchantCount  int64 `json:"underwater_merchant_count"`
	UnderwaterPaymentCount   int64 `json:"underwater_payment_count"`
}

// GetReconciliation compares what OrderxPay booked in commission against
// what the PSP actually charged, per merchant per period, plus a row-level
// list of the individual payments that came back underwater. It's the
// control the Fee Architecture brief calls the highest-leverage unbuilt
// thing: the aggregate revenue dashboard nets a leaky invoice against a
// profitable merchant and shows nothing wrong.
func (h *Handler) GetReconciliation(c *fiber.Ctx) error {
	periodStart, periodEnd, err := parseReportPeriod(c)
	if err != nil {
		return badRequest(c, err.Error())
	}
	params := db.GetMerchantRevenueBreakdownParams{
		PeriodStart: pgtype.Timestamptz{Time: periodStart, Valid: true},
		PeriodEnd:   pgtype.Timestamptz{Time: periodEnd, Valid: true},
	}

	rows, err := h.Queries.GetMerchantRevenueBreakdown(c.Context(), params)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load merchant revenue breakdown"})
	}

	under, err := h.Queries.GetUnderwaterPayments(c.Context(), db.GetUnderwaterPaymentsParams{
		PeriodStart: params.PeriodStart,
		PeriodEnd:   params.PeriodEnd,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load underwater payments"})
	}

	// The expected PSP cost is modelled off the global collection fee — the
	// component of the blended rate that exists to be passed straight to the
	// PSP. Per-merchant collection overrides aren't folded in; this figure is
	// a model-wide drift check, not a per-merchant settlement.
	expectedBps := int64(defaultCollectionFeeBps)
	if rule, ruleErr := h.Queries.GetGlobalFeeRule(c.Context()); ruleErr == nil {
		expectedBps = int64(rule.CollectionFeeBps)
	}

	summary, merchants := summarizeReconciliation(rows, expectedBps, len(under))

	uw := make([]underwaterPayment, 0, len(under))
	for _, u := range under {
		uw = append(uw, underwaterPayment{
			InvoiceReference:        u.InvoiceReference,
			MerchantID:              uuid.UUID(u.MerchantID.Bytes).String(),
			BusinessName:            u.BusinessName,
			AmountPesewas:           u.AmountPesewas,
			BookedCommissionPesewas: u.CommissionPesewas,
			PSPFeePesewas:           u.PspFeePesewas,
			ShortfallPesewas:        u.PspFeePesewas - u.CommissionPesewas,
			PaidAt:                  u.PaidAt.Time.Format(time.RFC3339),
		})
	}

	return c.JSON(fiber.Map{
		"period_start": periodStart.Format(dateLayout),
		"period_end":   periodEnd.AddDate(0, 0, -1).Format(dateLayout),
		"summary":      summary,
		"merchants":    merchants,
		"underwater":   uw,
	})
}

// summarizeReconciliation turns the per-merchant revenue rows into the
// reconciliation view: realized margin (booked commission minus the PSP fee
// actually charged) per merchant and in total, the modelled-vs-actual PSP
// cost drift, and counts of who came back underwater. Merchants with no
// payments in the period are dropped — there is nothing to reconcile.
// Rows are returned worst-margin-first so the losses sit at the top.
func summarizeReconciliation(
	rows []db.GetMerchantRevenueBreakdownRow,
	expectedCollectionFeeBps int64,
	underwaterPaymentCount int,
) (reconciliationSummary, []reconciliationMerchant) {
	merchants := make([]reconciliationMerchant, 0, len(rows))
	summary := reconciliationSummary{ExpectedCollectionFeeBps: expectedCollectionFeeBps}

	for _, m := range rows {
		if m.PaymentCount == 0 {
			continue
		}
		realized := m.CommissionPesewas - m.PspFeesPesewas
		var takeBps int64
		if m.GmvPesewas > 0 {
			takeBps = m.CommissionPesewas * 10000 / m.GmvPesewas
		}
		merchants = append(merchants, reconciliationMerchant{
			MerchantID:              uuid.UUID(m.MerchantID.Bytes).String(),
			BusinessName:            m.BusinessName,
			GMVPesewas:              m.GmvPesewas,
			BookedCommissionPesewas: m.CommissionPesewas,
			PSPFeePesewas:           m.PspFeesPesewas,
			RealizedMarginPesewas:   realized,
			EffectiveTakeRateBps:    takeBps,
			PaymentCount:            m.PaymentCount,
		})

		summary.GMVPesewas += m.GmvPesewas
		summary.BookedCommissionPesewas += m.CommissionPesewas
		summary.PSPFeeActualPesewas += m.PspFeesPesewas
		if realized < 0 {
			summary.UnderwaterMerchantCount++
		}
	}

	sort.SliceStable(merchants, func(i, j int) bool {
		return merchants[i].RealizedMarginPesewas < merchants[j].RealizedMarginPesewas
	})

	summary.PSPFeeExpectedPesewas = summary.GMVPesewas * expectedCollectionFeeBps / 10000
	summary.PSPFeeDriftPesewas = summary.PSPFeeActualPesewas - summary.PSPFeeExpectedPesewas
	summary.RealizedMarginPesewas = summary.BookedCommissionPesewas - summary.PSPFeeActualPesewas
	if summary.GMVPesewas > 0 {
		summary.RealizedMarginBps = summary.RealizedMarginPesewas * 10000 / summary.GMVPesewas
	}
	summary.UnderwaterPaymentCount = int64(underwaterPaymentCount)

	return summary, merchants
}
