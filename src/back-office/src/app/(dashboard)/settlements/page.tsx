import { listAllSettlements } from "@/lib/settlements";
import { listMerchants } from "@/lib/merchants";
import { ApiError } from "@/lib/session";
import { formatPesewas } from "@/lib/money";
import { GenerateSettlementForm } from "./generate-form";
import { SettlementStatusActions } from "./status-actions";
import { CsvExportButton } from "./csv-export-button";

const STATUS_STYLES: Record<string, string> = {
  pending: "bg-amber-100 text-amber-800",
  processing: "bg-blue-100 text-blue-800",
  paid: "bg-green-100 text-green-800",
  failed: "bg-red-100 text-red-800",
};

function formatDate(d: string) {
  return new Date(d).toLocaleDateString("en-GH", {
    day: "2-digit",
    month: "short",
    year: "numeric",
  });
}

export default async function SettlementsPage() {
  let settlements, merchants;
  try {
    [settlements, merchants] = await Promise.all([
      listAllSettlements(),
      listMerchants(),
    ]);
  } catch (err) {
    if (err instanceof ApiError && err.status === 403) {
      return (
        <p className="text-sm text-neutral-500">
          You don&apos;t have permission to view settlements (requires
          settlements.view).
        </p>
      );
    }
    throw err;
  }

  return (
    <div className="space-y-6">
      <div>
        <div className="flex items-baseline gap-2">
          <h1 className="text-2xl font-semibold text-neutral-900">
            Collections, Settlement &amp; Payout Ledger
          </h1>
          <span className="text-xs font-mono text-neutral-400">
            Section 7.2
          </span>
        </div>
        <p className="text-sm text-neutral-500">
          Gross collections in, PSP fees, OrderxPay commission, and net
          amount payable per merchant. Generating a batch settles every
          not-yet-settled successful payment in the chosen period; marking a
          settlement paid records that the payout was actually sent — Phase
          1 payouts are executed manually, outside this system.
        </p>
      </div>

      <div className="flex flex-wrap items-start justify-between gap-3">
        <GenerateSettlementForm merchants={merchants} />
        <CsvExportButton settlements={settlements} />
      </div>

      {settlements.length === 0 ? (
        <p className="text-sm text-neutral-500">No settlements yet.</p>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-neutral-200">
          <table className="w-full text-sm">
            <thead className="bg-neutral-50 text-left text-xs uppercase tracking-wide text-neutral-500">
              <tr>
                <th className="px-4 py-2">Merchant</th>
                <th className="px-4 py-2">Period</th>
                <th className="px-4 py-2 text-right">Gross collected</th>
                <th className="px-4 py-2 text-right">PSP fees</th>
                <th className="px-4 py-2 text-right">Commission</th>
                <th className="px-4 py-2 text-right">Net payout</th>
                <th className="px-4 py-2">Status</th>
                <th className="px-4 py-2">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-neutral-100">
              {settlements.map((s) => (
                <tr key={s.id} className="hover:bg-neutral-50">
                  <td className="px-4 py-2 font-medium text-neutral-900">
                    {s.merchant_business_name}
                  </td>
                  <td className="px-4 py-2 text-neutral-600">
                    {formatDate(s.period_start)} – {formatDate(s.period_end)}
                  </td>
                  <td className="px-4 py-2 text-right text-neutral-600">
                    {formatPesewas(s.gross_collections_pesewas)}
                  </td>
                  <td className="px-4 py-2 text-right text-neutral-600">
                    {formatPesewas(s.psp_fees_pesewas)}
                  </td>
                  <td className="px-4 py-2 text-right text-neutral-600">
                    {formatPesewas(s.commission_pesewas)}
                  </td>
                  <td className="px-4 py-2 text-right font-medium text-neutral-900">
                    {formatPesewas(s.net_payout_pesewas)}
                  </td>
                  <td className="px-4 py-2">
                    <span
                      className={`rounded-full px-2 py-0.5 text-xs font-medium ${STATUS_STYLES[s.status]}`}
                    >
                      {s.status}
                    </span>
                  </td>
                  <td className="px-4 py-2">
                    <SettlementStatusActions
                      settlementId={s.id}
                      status={s.status}
                    />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
