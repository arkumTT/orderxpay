"use client";

import type { ReconciliationResponse } from "@/lib/types";

function csvCell(v: string | number): string {
  const s = String(v);
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

function toCSV(rows: (string | number)[][]): string {
  return rows.map((r) => r.map(csvCell).join(",")).join("\n");
}

function ghs(pesewas: number): string {
  return (pesewas / 100).toFixed(2);
}

// Client-side export — the data is already on the page, same pattern as the
// revenue report. Finance reconciles this against the Paystack settlement
// statement, so the per-merchant and per-payment rows both go in the file.
export function CsvExportButton({
  report,
}: {
  report: ReconciliationResponse;
}) {
  function handleExport() {
    const s = report.summary;
    const lines = [
      [
        `OrderxPay margin reconciliation: ${report.period_start} to ${report.period_end}`,
      ],
      [],
      ["Summary"],
      ["GMV (GHS)", ghs(s.gmv_pesewas)],
      ["Booked commission (GHS)", ghs(s.booked_commission_pesewas)],
      ["PSP fee — actual (GHS)", ghs(s.psp_fee_actual_pesewas)],
      [
        `PSP fee — expected at ${(s.expected_collection_fee_bps / 100).toFixed(2)}% (GHS)`,
        ghs(s.psp_fee_expected_pesewas),
      ],
      ["PSP fee — drift (GHS)", ghs(s.psp_fee_drift_pesewas)],
      ["Realized margin (GHS)", ghs(s.realized_margin_pesewas)],
      ["Realized margin (%)", (s.realized_margin_bps / 100).toFixed(2)],
      ["Underwater merchants", s.underwater_merchant_count],
      ["Underwater payments", s.underwater_payment_count],
      [],
      ["By merchant"],
      [
        "Merchant",
        "GMV (GHS)",
        "Booked commission (GHS)",
        "PSP fee (GHS)",
        "Realized margin (GHS)",
        "Effective take rate (%)",
        "Payments",
      ],
      ...report.merchants.map((m) => [
        m.business_name,
        ghs(m.gmv_pesewas),
        ghs(m.booked_commission_pesewas),
        ghs(m.psp_fee_pesewas),
        ghs(m.realized_margin_pesewas),
        (m.effective_take_rate_bps / 100).toFixed(2),
        m.payment_count,
      ]),
      [],
      ["Underwater payments"],
      [
        "Invoice",
        "Merchant",
        "Amount paid (GHS)",
        "Booked commission (GHS)",
        "PSP fee (GHS)",
        "Shortfall (GHS)",
        "Paid at",
      ],
      ...report.underwater.map((u) => [
        u.invoice_reference,
        u.business_name,
        ghs(u.amount_pesewas),
        ghs(u.booked_commission_pesewas),
        ghs(u.psp_fee_pesewas),
        ghs(u.shortfall_pesewas),
        u.paid_at,
      ]),
    ];

    const csv = toCSV(lines as (string | number)[][]);
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `orderxpay-reconciliation-${report.period_start}-to-${report.period_end}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <button
      type="button"
      onClick={handleExport}
      className="rounded-md border border-neutral-300 px-3 py-2 text-sm font-medium text-neutral-700 hover:bg-neutral-50"
    >
      Export CSV
    </button>
  );
}
