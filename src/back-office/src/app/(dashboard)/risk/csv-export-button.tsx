"use client";

import type { RiskFlagWithMerchant } from "@/lib/types";

function csvCell(v: string | number): string {
  const s = String(v);
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

function toCSV(rows: (string | number)[][]): string {
  return rows.map((r) => r.map(csvCell).join(",")).join("\n");
}

function isoDate(d: Date) {
  return d.toISOString().slice(0, 10);
}

// Client-side export, same approach as the reporting/settlements/disputes
// pages' exports — the flag list is already loaded on the page, no new
// endpoint needed.
export function CsvExportButton({
  flags,
}: {
  flags: RiskFlagWithMerchant[];
}) {
  function handleExport() {
    const lines = [
      [
        "Merchant",
        "Flag type",
        "Details",
        "Status",
        "Resolution notes",
        "Created at",
        "Reviewed at",
      ],
      ...flags.map((f) => [
        f.merchant_business_name,
        f.flag_type,
        f.details,
        f.status,
        f.resolution_notes ?? "",
        f.created_at,
        f.reviewed_at ?? "",
      ]),
    ];

    const csv = toCSV(lines as (string | number)[][]);
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `orderxpay-risk-flags-${isoDate(new Date())}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <button
      type="button"
      onClick={handleExport}
      disabled={flags.length === 0}
      className="rounded-md border border-neutral-300 px-3 py-2 text-sm font-medium text-neutral-700 hover:bg-neutral-50 disabled:opacity-50"
    >
      Export CSV
    </button>
  );
}
