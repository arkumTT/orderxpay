"use client";

import type { SettlementWithMerchant } from "@/lib/types";

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

function isoDate(d: Date) {
  return d.toISOString().slice(0, 10);
}

// Client-side export, same approach as the reporting page's CSV export —
// the settlement list is already loaded on the page, so there's no need
// for a dedicated CSV endpoint.
export function CsvExportButton({
  settlements,
}: {
  settlements: SettlementWithMerchant[];
}) {
  function handleExport() {
    const lines = [
      ["Merchant", "Period start", "Period end", "Gross collections (GHS)", "PSP fees (GHS)", "Commission (GHS)", "Net payout (GHS)", "Status"],
      ...settlements.map((s) => [
        s.merchant_business_name,
        s.period_start,
        s.period_end,
        ghs(s.gross_collections_pesewas),
        ghs(s.psp_fees_pesewas),
        ghs(s.commission_pesewas),
        ghs(s.net_payout_pesewas),
        s.status,
      ]),
    ];

    const csv = toCSV(lines as (string | number)[][]);
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `orderxpay-settlements-${isoDate(new Date())}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <button
      type="button"
      onClick={handleExport}
      disabled={settlements.length === 0}
      className="rounded-md border border-neutral-300 px-3 py-2 text-sm font-medium text-neutral-700 hover:bg-neutral-50 disabled:opacity-50"
    >
      Export CSV
    </button>
  );
}
