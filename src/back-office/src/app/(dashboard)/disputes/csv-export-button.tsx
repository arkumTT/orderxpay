"use client";

import type { DisputeWithContext } from "@/lib/types";

function csvCell(v: string | number): string {
  const s = String(v);
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

function toCSV(rows: (string | number)[][]): string {
  return rows.map((r) => r.map(csvCell).join(",")).join("\n");
}

function ghs(pesewas: number | null): string {
  return pesewas == null ? "" : (pesewas / 100).toFixed(2);
}

function isoDate(d: Date) {
  return d.toISOString().slice(0, 10);
}

// Client-side export, same approach as the reporting/settlements pages —
// the dispute list is already loaded on the page, so there's no need for a
// dedicated CSV endpoint.
export function CsvExportButton({
  disputes,
}: {
  disputes: DisputeWithContext[];
}) {
  function handleExport() {
    const lines = [
      [
        "Invoice reference",
        "Merchant",
        "Customer",
        "Reason",
        "Description",
        "Status",
        "Resolution notes",
        "Refund amount (GHS)",
        "Created at",
        "Resolved at",
      ],
      ...disputes.map((d) => [
        d.invoice_reference,
        d.merchant_business_name,
        d.customer_contact,
        d.reason_category,
        d.description ?? "",
        d.status,
        d.resolution_notes ?? "",
        ghs(d.refund_amount_pesewas),
        d.created_at,
        d.resolved_at ?? "",
      ]),
    ];

    const csv = toCSV(lines as (string | number)[][]);
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `orderxpay-disputes-${isoDate(new Date())}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <button
      type="button"
      onClick={handleExport}
      disabled={disputes.length === 0}
      className="rounded-md border border-neutral-300 px-3 py-2 text-sm font-medium text-neutral-700 hover:bg-neutral-50 disabled:opacity-50"
    >
      Export CSV
    </button>
  );
}
