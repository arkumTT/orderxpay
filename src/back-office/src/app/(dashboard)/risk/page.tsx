import { listRiskFlags } from "@/lib/risk";
import { ApiError } from "@/lib/session";
import type { RiskFlagWithMerchant } from "@/lib/types";
import { RunScanButton } from "./run-scan-button";
import { FlagActions } from "./flag-actions";

const STATUS_STYLES: Record<string, string> = {
  open: "bg-amber-100 text-amber-800",
  dismissed: "bg-neutral-100 text-neutral-600",
  escalated: "bg-red-100 text-red-800",
};

const TYPE_LABELS: Record<string, string> = {
  duplicate_ghana_card: "Duplicate Ghana Card",
  velocity_spike: "Velocity spike",
};

function formatDate(d: string) {
  return new Date(d).toLocaleDateString("en-GH", {
    day: "2-digit",
    month: "short",
    year: "numeric",
  });
}

function FlagRow({
  f,
  showActions,
}: {
  f: RiskFlagWithMerchant;
  showActions: boolean;
}) {
  return (
    <tr className="hover:bg-neutral-50">
      <td className="px-4 py-3 align-top font-medium text-neutral-900">
        {f.merchant_business_name}
      </td>
      <td className="px-4 py-3 align-top">
        <div className="text-neutral-700">
          {TYPE_LABELS[f.flag_type] ?? f.flag_type}
        </div>
        <div className="text-xs text-neutral-500">{f.details}</div>
        <div className="text-xs text-neutral-400">{formatDate(f.created_at)}</div>
      </td>
      <td className="px-4 py-3 align-top">
        <span
          className={`rounded-full px-2 py-0.5 text-xs font-medium ${STATUS_STYLES[f.status]}`}
        >
          {f.status}
        </span>
        {f.resolution_notes && (
          <div className="mt-1 text-xs text-neutral-500">{f.resolution_notes}</div>
        )}
      </td>
      <td className="px-4 py-3 align-top">
        {showActions ? (
          <FlagActions flagId={f.id} />
        ) : (
          <span className="text-xs text-neutral-400">
            {f.reviewed_at ? formatDate(f.reviewed_at) : "—"}
          </span>
        )}
      </td>
    </tr>
  );
}

export default async function RiskPage() {
  let flags: RiskFlagWithMerchant[];
  try {
    flags = await listRiskFlags();
  } catch (err) {
    if (err instanceof ApiError && err.status === 403) {
      return (
        <p className="text-sm text-neutral-500">
          You don&apos;t have permission to view the risk queue (requires
          risk.view).
        </p>
      );
    }
    throw err;
  }

  const open = flags.filter((f) => f.status === "open");
  const resolved = flags.filter((f) => f.status !== "open");

  return (
    <div className="space-y-6">
      <div>
        <div className="flex items-baseline gap-2">
          <h1 className="text-2xl font-semibold text-neutral-900">
            Risk &amp; Fraud Monitoring
          </h1>
          <span className="text-xs font-mono text-neutral-400">
            Section 7.6
          </span>
        </div>
        <p className="text-sm text-neutral-500">
          Duplicate-Ghana-Card detection across merchant accounts and
          invoice velocity spikes, feeding the AML/KYC review obligations in
          Section 2.2. Device-fingerprint duplicate detection isn&apos;t
          built — no device signal is collected yet.
        </p>
      </div>

      <RunScanButton />

      <div>
        <h2 className="mb-2 text-sm font-semibold text-neutral-700">
          Open ({open.length})
        </h2>
        {open.length === 0 ? (
          <p className="text-sm text-neutral-500">
            No open flags. Run a scan to check for new ones.
          </p>
        ) : (
          <div className="overflow-x-auto rounded-lg border border-neutral-200">
            <table className="w-full text-sm">
              <thead className="bg-neutral-50 text-left text-xs uppercase tracking-wide text-neutral-500">
                <tr>
                  <th className="px-4 py-2">Merchant</th>
                  <th className="px-4 py-2">Finding</th>
                  <th className="px-4 py-2">Status</th>
                  <th className="px-4 py-2">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-neutral-100">
                {open.map((f) => (
                  <FlagRow key={f.id} f={f} showActions />
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
                  <th className="px-4 py-2">Merchant</th>
                  <th className="px-4 py-2">Finding</th>
                  <th className="px-4 py-2">Status</th>
                  <th className="px-4 py-2">Reviewed</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-neutral-100">
                {resolved.map((f) => (
                  <FlagRow key={f.id} f={f} showActions={false} />
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
