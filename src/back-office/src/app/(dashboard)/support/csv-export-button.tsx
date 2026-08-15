"use client";

import type { SupportTransactionSummary } from "@/lib/types";

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

// Client-side export, same approach as the other pages' exports — the
// matched transactions are already loaded on the page, no new endpoint
// needed. Only the transaction results are exported: matched merchants are
// already covered by the merchants list page's own export.
export function CsvExportButton({
  invoices,
}: {
  invoices: SupportTransactionSummary[];
}) {
  function handleExport() {
    const lines = [
      [
        "Reference",
        "Merchant",
        "Customer",
        "Total (GHS)",
        "Status",
        "Created at",
      ],
      ...invoices.map((inv) => [
        inv.reference,
        inv.merchant_business_name,
        inv.customer_contact,
        ghs(inv.total_pesewas),
        inv.status,
        inv.created_at,
      ]),
    ];

    const csv = toCSV(lines as (string | number)[][]);
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `orderxpay-support-search-${isoDate(new Date())}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <button
      type="button"
      onClick={handleExport}
      disabled={invoices.length === 0}
      className="rounded-md border border-neutral-300 px-3 py-2 text-sm font-medium text-neutral-700 hover:bg-neutral-50 disabled:opacity-50"
    >
      Export CSV
    </button>
  );
}
