"use client";

import type { KYCSubmissionWithMerchant } from "@/lib/types";

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

// Client-side export, same approach as the reporting/settlements/disputes/
// risk pages' exports — the submission list is already loaded on the page,
// no new endpoint needed.
export function CsvExportButton({
  submissions,
}: {
  submissions: KYCSubmissionWithMerchant[];
}) {
  function handleExport() {
    const lines = [
      [
        "Merchant",
        "Requested tier",
        "Ghana Card number",
        "Business reg. number",
        "Notes",
        "Status",
        "Reviewer notes",
        "Submitted at",
        "Reviewed at",
      ],
      ...submissions.map((s) => [
        s.merchant_business_name,
        s.requested_tier,
        s.ghana_card_number,
        s.business_reg_number ?? "",
        s.notes ?? "",
        s.status,
        s.reviewer_notes ?? "",
        s.created_at,
        s.reviewed_at ?? "",
      ]),
    ];

    const csv = toCSV(lines as (string | number)[][]);
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `orderxpay-kyc-submissions-${isoDate(new Date())}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <button
      type="button"
      onClick={handleExport}
      disabled={submissions.length === 0}
      className="rounded-md border border-neutral-300 px-3 py-2 text-sm font-medium text-neutral-700 hover:bg-neutral-50 disabled:opacity-50"
    >
      Export CSV
    </button>
  );
}
