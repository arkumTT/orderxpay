"use client";

import type { ReportingResponse } from "@/lib/types";

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

// Client-side export (Section 7.5's "exportable reports for finance/
// accounting and investor reporting") — the report data is already loaded
// on the page, so there's no need for a dedicated CSV endpoint.
export function CsvExportButton({ report }: { report: ReportingResponse }) {
  function handleExport() {
    const lines = [
      [`OrderxPay revenue report: ${report.period_start} to ${report.period_end}`],
      [],
      ["Summary"],
      ["GMV (GHS)", ghs(report.summary.gmv_pesewas)],
      ["Commission (GHS)", ghs(report.summary.commission_pesewas)],
      ["PSP fees (GHS)", ghs(report.summary.psp_fees_pesewas)],
      ["Net margin (GHS)", ghs(report.summary.net_margin_pesewas)],
      ["Blended take rate (%)", (report.summary.blended_take_rate_bps / 100).toFixed(2)],
      ["Active merchants", report.summary.active_merchants],
      ["Dormant merchants", report.summary.dormant_merchants],
      [],
      ["Daily"],
      ["Date", "GMV (GHS)", "Commission (GHS)", "PSP fees (GHS)"],
      ...report.daily.map((d) => [d.day, ghs(d.gmv_pesewas), ghs(d.commission_pesewas), ghs(d.psp_fees_pesewas)]),
      [],
      ["By merchant"],
      ["Merchant", "Status", "GMV (GHS)", "Commission (GHS)", "PSP fees (GHS)", "Payments"],
      ...report.merchants.map((m) => [
        m.business_name,
        m.merchant_status,
        ghs(m.gmv_pesewas),
        ghs(m.commission_pesewas),
        ghs(m.psp_fees_pesewas),
        m.payment_count,
      ]),
    ];

    const csv = toCSV(lines as (string | number)[][]);
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `orderxpay-revenue-${report.period_start}-to-${report.period_end}.csv`;
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
