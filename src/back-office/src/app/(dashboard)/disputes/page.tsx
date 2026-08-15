import Link from "next/link";
import { listDisputes } from "@/lib/disputes";
import { ApiError } from "@/lib/session";
import { formatPesewas } from "@/lib/money";
import type { DisputeWithContext } from "@/lib/types";
import { LogDisputeForm } from "./log-dispute-form";
import { DisputeActions } from "./dispute-actions";
import { CsvExportButton } from "./csv-export-button";

const STATUS_STYLES: Record<string, string> = {
  open: "bg-amber-100 text-amber-800",
  investigating: "bg-blue-100 text-blue-800",
  resolved_refunded: "bg-green-100 text-green-800",
  resolved_denied: "bg-red-100 text-red-800",
};

const REASON_LABELS: Record<string, string> = {
  not_received: "Goods not received",
  wrong_item: "Wrong item",
  damaged: "Damaged",
  duplicate_charge: "Duplicate charge",
  not_as_described: "Not as described",
  other: "Other",
};

function formatDate(d: string) {
  return new Date(d).toLocaleDateString("en-GH", {
    day: "2-digit",
    month: "short",
    year: "numeric",
  });
}

function DisputeRow({
  d,
  showActions,
}: {
  d: DisputeWithContext;
  showActions: boolean;
}) {
  return (
    <tr className="hover:bg-neutral-50">
      <td className="px-4 py-3 align-top">
        <div className="font-medium text-neutral-900">{d.invoice_reference}</div>
        <Link
          href={`/merchants`}
          className="text-xs text-neutral-400 hover:underline"
        >
          {d.merchant_business_name}
        </Link>
        <div className="text-xs text-neutral-400">{d.customer_contact}</div>
      </td>
      <td className="px-4 py-3 align-top text-neutral-600">
        <div>{REASON_LABELS[d.reason_category] ?? d.reason_category}</div>
        {d.description && (
          <div className="text-xs text-neutral-400">{d.description}</div>
        )}
        <div className="text-xs text-neutral-400">{formatDate(d.created_at)}</div>
      </td>
      <td className="px-4 py-3 align-top">
        <span
          className={`rounded-full px-2 py-0.5 text-xs font-medium ${STATUS_STYLES[d.status]}`}
        >
          {d.status.replace("_", " ")}
        </span>
        {d.resolution_notes && (
          <div className="mt-1 text-xs text-neutral-500">{d.resolution_notes}</div>
        )}
        {d.status === "resolved_refunded" && d.refund_amount_pesewas != null && (
          <div className="mt-1 text-xs font-medium text-green-700">
            Refunded {formatPesewas(d.refund_amount_pesewas)}
          </div>
        )}
      </td>
      <td className="px-4 py-3 align-top">
        {showActions ? (
          <DisputeActions
            disputeId={d.id}
            status={d.status as "open" | "investigating"}
          />
        ) : (
          <span className="text-xs text-neutral-400">
            {d.resolved_at ? formatDate(d.resolved_at) : "—"}
          </span>
        )}
      </td>
    </tr>
  );
}

export default async function DisputesPage() {
  let disputes: DisputeWithContext[];
  try {
    disputes = await listDisputes();
  } catch (err) {
    if (err instanceof ApiError && err.status === 403) {
      return (
        <p className="text-sm text-neutral-500">
          You don&apos;t have permission to view disputes (requires
          disputes.view).
        </p>
      );
    }
    throw err;
  }

  const open = disputes.filter(
    (d) => d.status === "open" || d.status === "investigating",
  );
  const resolved = disputes.filter(
    (d) => d.status === "resolved_refunded" || d.status === "resolved_denied",
  );

  return (
    <div className="space-y-6">
      <div>
        <div className="flex items-baseline gap-2">
          <h1 className="text-2xl font-semibold text-neutral-900">
            Dispute &amp; Refund Management
          </h1>
          <span className="text-xs font-mono text-neutral-400">
            Section 7.7
          </span>
        </div>
        <p className="text-sm text-neutral-500">
          Log a customer complaint against an invoice, track it to
          resolution, and refund through Paystack when warranted.
        </p>
      </div>

      <div className="flex flex-wrap items-start justify-between gap-3">
        <LogDisputeForm />
        <CsvExportButton disputes={disputes} />
      </div>

      <div>
        <h2 className="mb-2 text-sm font-semibold text-neutral-700">
          Open ({open.length})
        </h2>
        {open.length === 0 ? (
          <p className="text-sm text-neutral-500">No open disputes.</p>
        ) : (
          <div className="overflow-x-auto rounded-lg border border-neutral-200">
            <table className="w-full text-sm">
              <thead className="bg-neutral-50 text-left text-xs uppercase tracking-wide text-neutral-500">
                <tr>
                  <th className="px-4 py-2">Invoice</th>
                  <th className="px-4 py-2">Reason</th>
                  <th className="px-4 py-2">Status</th>
                  <th className="px-4 py-2">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-neutral-100">
                {open.map((d) => (
                  <DisputeRow key={d.id} d={d} showActions />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {resolved.length > 0 && (
        <div>
          <h2 className="mb-2 text-sm font-semibold text-neutral-700">
            Resolved
          </h2>
          <div className="overflow-x-auto rounded-lg border border-neutral-200">
            <table className="w-full text-sm">
              <thead className="bg-neutral-50 text-left text-xs uppercase tracking-wide text-neutral-500">
                <tr>
                  <th className="px-4 py-2">Invoice</th>
                  <th className="px-4 py-2">Reason</th>
                  <th className="px-4 py-2">Status</th>
                  <th className="px-4 py-2">Resolved</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-neutral-100">
                {resolved.map((d) => (
                  <DisputeRow key={d.id} d={d} showActions={false} />
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
