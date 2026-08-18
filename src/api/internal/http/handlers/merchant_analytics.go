package handlers

import (
	"encoding/csv"
	"fmt"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5/pgtype"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

// GetMerchantAnalytics backs the mobile Records "Insights" view (Section
// 4.7): best-selling items, daily collections, average order value, and
// repeat customers, all scoped to the requesting merchant's own paid/
// partially-paid invoices in the requested period. Reuses the
// period_start/period_end query convention from parseReportPeriod
// (reporting.go).
func (h *Handler) GetMerchantAnalytics(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}
	periodStart, periodEnd, err := parseReportPeriod(c)
	if err != nil {
		return badRequest(c, err.Error())
	}

	periodStartPg := pgtype.Timestamptz{Time: periodStart, Valid: true}
	periodEndPg := pgtype.Timestamptz{Time: periodEnd, Valid: true}

	bestSelling, err := h.Queries.GetMerchantBestSellingItems(c.Context(), db.GetMerchantBestSellingItemsParams{
		MerchantID:  merchantID,
		PeriodStart: periodStartPg,
		PeriodEnd:   periodEndPg,
		RowLimit:    10,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load best-selling items"})
	}

	daily, err := h.Queries.GetMerchantDailyCollections(c.Context(), db.GetMerchantDailyCollectionsParams{
		MerchantID:  merchantID,
		PeriodStart: periodStartPg,
		PeriodEnd:   periodEndPg,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load daily collections"})
	}

	stats, err := h.Queries.GetMerchantOrderStats(c.Context(), db.GetMerchantOrderStatsParams{
		MerchantID:  merchantID,
		PeriodStart: periodStartPg,
		PeriodEnd:   periodEndPg,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load order stats"})
	}

	repeatCustomers, err := h.Queries.GetMerchantRepeatCustomers(c.Context(), db.GetMerchantRepeatCustomersParams{
		MerchantID:  merchantID,
		PeriodStart: periodStartPg,
		PeriodEnd:   periodEndPg,
		RowLimit:    10,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load repeat customers"})
	}

	return c.JSON(fiber.Map{
		"period_start":       periodStart.Format(dateLayout),
		"period_end":         periodEnd.AddDate(0, 0, -1).Format(dateLayout),
		"best_selling_items": bestSelling,
		"daily_collections":  daily,
		"order_stats":        stats,
		"repeat_customers":   repeatCustomers,
	})
}

// ExportMerchantRecords streams the merchant's own records sheet as CSV for
// their own bookkeeping/accountant (Section 4.7). Unlike GetMerchantAnalytics
// this includes every invoice status in the period, not just paid/
// partially_paid — an accountant needs to see declined/expired invoices too.
// PDF export isn't built: it would need a new dependency (a Go PDF library)
// that isn't in this codebase yet, so this is CSV-only for now.
func (h *Handler) ExportMerchantRecords(c *fiber.Ctx) error {
	merchantID, err := parseUUIDParam(c, "id")
	if err != nil {
		return badRequest(c, "invalid merchant id")
	}
	periodStart, periodEnd, err := parseReportPeriod(c)
	if err != nil {
		return badRequest(c, err.Error())
	}

	rows, err := h.Queries.ListMerchantInvoicesForExport(c.Context(), db.ListMerchantInvoicesForExportParams{
		MerchantID:  merchantID,
		PeriodStart: pgtype.Timestamptz{Time: periodStart, Valid: true},
		PeriodEnd:   pgtype.Timestamptz{Time: periodEnd, Valid: true},
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to load records for export"})
	}

	filename := fmt.Sprintf("orderxpay-records-%s-to-%s.csv", periodStart.Format(dateLayout), periodEnd.AddDate(0, 0, -1).Format(dateLayout))
	c.Set(fiber.HeaderContentType, "text/csv")
	c.Set(fiber.HeaderContentDisposition, fmt.Sprintf(`attachment; filename="%s"`, filename))

	w := csv.NewWriter(c.Response().BodyWriter())
	header := []string{"Reference", "Customer", "Date", "Items", "Status", "Amount Invoiced (GHS)", "Amount Paid (GHS)", "Outstanding (GHS)", "Channel"}
	if err := w.Write(header); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to write export"})
	}
	for _, r := range rows {
		record := []string{
			r.Reference,
			r.CustomerContact,
			r.CreatedAt.Time.Format("2006-01-02 15:04"),
			string(r.ItemsSummary),
			r.Status,
			pesewasToGHS(r.AmountInvoicedPesewas),
			pesewasToGHS(r.AmountPaidPesewas),
			pesewasToGHS(r.OutstandingPesewas),
			string(r.Channel),
		}
		if err := w.Write(record); err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to write export"})
		}
	}
	w.Flush()
	if err := w.Error(); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to write export"})
	}
	return nil
}

// pesewasToGHS renders a pesewas integer as a plain decimal GHS string
// (e.g. 520 -> "5.20") without float division, for the CSV export.
func pesewasToGHS(pesewas int64) string {
	sign := ""
	if pesewas < 0 {
		sign = "-"
		pesewas = -pesewas
	}
	return fmt.Sprintf("%s%d.%02d", sign, pesewas/100, pesewas%100)
}
