"use client";

import type { WebhookDelivery } from "@/lib/types";

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
// risk/KYC/admin-users pages' exports — the delivery log is already loaded
// on the page, no new endpoint needed. Only the webhook delivery log is
// exported here: the provider cards are a fixed 5-row config list (and
// never carry secret values), and the delivery-provider list is small
// config too — neither is the kind of growing, analyzable data this export
// is for.
export function CsvExportButton({
  deliveries,
}: {
  deliveries: WebhookDelivery[];
}) {
  function handleExport() {
    const lines = [
      [
        "Received at",
        "Provider",
        "Event type",
        "Reference",
        "Signature valid",
        "Processed OK",
        "Error message",
      ],
      ...deliveries.map((d) => [
        d.received_at,
        d.provider,
        d.event_type ?? "",
        d.reference ?? "",
        d.signature_valid ? "yes" : "no",
        d.processed_ok ? "yes" : "no",
        d.error_message ?? "",
      ]),
    ];

    const csv = toCSV(lines as (string | number)[][]);
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `orderxpay-webhook-deliveries-${isoDate(new Date())}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <button
      type="button"
      onClick={handleExport}
      disabled={deliveries.length === 0}
      className="rounded-md border border-neutral-300 px-3 py-2 text-sm font-medium text-neutral-700 hover:bg-neutral-50 disabled:opacity-50"
    >
      Export CSV
    </button>
  );
}
