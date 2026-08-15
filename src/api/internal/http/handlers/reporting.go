package handlers

import (
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5/pgtype"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

type reportingSummary struct {
	GMVPesewas         int64 `json:"gmv_pesewas"`
	PSPFeesPesewas     int64 `json:"psp_fees_pesewas"`
	CommissionPesewas  int64 `json:"commission_pesewas"`
	NetMarginPesewas   int64 `json:"net_margin_pesewas"`    // commission - PSP fees; WhatsApp/SMS costs aren't tracked anywhere yet, see GetReporting doc comment
	BlendedTakeRateBps int64 `json:"blended_take_rate_bps"` // commission / GMV, in basis points
	ActiveMerchants    int64 `json:"active_merchants"`
	DormantMerchants   int64 `json:"dormant_merchants"`
	TotalMerchants     int64 `json:"total_merchants"`
}

// GetReporting is the Section 7.5 revenue dashboard. Commission revenue,
// GMV, active-vs-dormant, and blended take-rate are all real, computed from
// live invoice/payment data. Cost tracking only covers PSP fees — WhatsApp
// BSP/message costs and SMS costs aren't in net_margin_pesewas because
// nothing in this codebase integrates a messaging provider yet (Section 4.4
// is still a stub), so there's no real cost data to show for them.
func (h *Handler) GetReporting(c *fiber.Ctx) error {
	periodStart, periodEnd, err := parseReportPeriod(c)
	if err != nil {
		return badRequest(c, err.Error())
	}

	params := db.GetMerchantRevenueBreakdownParams{
		PeriodStart: pgtype.Timestamptz{Time: periodStart, Valid: true},
		PeriodEnd:   pgtype.Timestamptz{Time: periodEnd, Valid: true},
	}
	merchants, err := h.Queries.GetMerchantRevenueBreakdown(c.Context(), params)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load merchant revenue breakdown"})
	}

	daily, err := h.Queries.GetDailyRevenue(c.Context(), db.GetDailyRevenueParams{
		PeriodStart: params.PeriodStart,
		PeriodEnd:   params.PeriodEnd,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load daily revenue"})
	}

	var summary reportingSummary
	for _, m := range merchants {
		summary.GMVPesewas += m.GmvPesewas
		summary.PSPFeesPesewas += m.PspFeesPesewas
		summary.CommissionPesewas += m.CommissionPesewas
		summary.TotalMerchants++
		if m.PaymentCount > 0 {
			summary.ActiveMerchants++
		}
	}
	summary.DormantMerchants = summary.TotalMerchants - summary.ActiveMerchants
	summary.NetMarginPesewas = summary.CommissionPesewas - summary.PSPFeesPesewas
	if summary.GMVPesewas > 0 {
		summary.BlendedTakeRateBps = summary.CommissionPesewas * 10000 / summary.GMVPesewas
	}

	return c.JSON(fiber.Map{
		"period_start": periodStart.Format(dateLayout),
		"period_end":   periodEnd.AddDate(0, 0, -1).Format(dateLayout), // report back the inclusive end date the caller asked for
		"summary":      summary,
		"daily":        daily,
		"merchants":    merchants,
	})
}

// parseReportPeriod reads period_start/period_end (YYYY-MM-DD, both
// inclusive) from the query string, defaulting to the trailing 30 days.
// dateLayout is shared with settlements.go.
func parseReportPeriod(c *fiber.Ctx) (start, end time.Time, err error) {
	endStr := c.Query("period_end")
	startStr := c.Query("period_start")

	if endStr == "" {
		end = time.Now().UTC().Truncate(24*time.Hour).AddDate(0, 0, 1)
	} else {
		endDate, parseErr := time.Parse(dateLayout, endStr)
		if parseErr != nil {
			return time.Time{}, time.Time{}, parseErr
		}
		end = endDate.AddDate(0, 0, 1) // inclusive end date -> exclusive upper bound
	}

	if startStr == "" {
		start = end.AddDate(0, 0, -30)
	} else {
		start, err = time.Parse(dateLayout, startStr)
		if err != nil {
			return time.Time{}, time.Time{}, err
		}
	}

	return start, end, nil
}
