"use client";

import type { FeeRuleOverride } from "@/lib/types";

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

// Client-side export, same approach as the other pages' exports — the
// override list is already loaded on the page, no new endpoint needed.
// Only the merchant-override table is exported: the global default is a
// single record, not a list, and feature flags are small fixed config
// rather than growing, analyzable data.
export function CsvExportButton({
  overrides,
}: {
  overrides: FeeRuleOverride[];
}) {
  function handleExport() {
    const lines = [
      ["Merchant", "Commission rate (%)", "Allocation", "Updated at"],
      ...overrides.map((o) => [
        o.merchant_business_name,
        (o.commission_bps / 100).toFixed(2),
        o.allocation_type,
        o.updated_at,
      ]),
    ];

    const csv = toCSV(lines as (string | number)[][]);
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `orderxpay-pricing-overrides-${isoDate(new Date())}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <button
      type="button"
      onClick={handleExport}
      disabled={overrides.length === 0}
      className="rounded-md border border-neutral-300 px-3 py-2 text-sm font-medium text-neutral-700 hover:bg-neutral-50 disabled:opacity-50"
    >
      Export CSV
    </button>
  );
}
