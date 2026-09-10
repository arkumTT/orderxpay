import { getReconciliation } from "@/lib/reconciliation";
import { ApiError } from "@/lib/session";
import { formatPesewas } from "@/lib/money";
import type {
  ReconciliationMerchant,
  UnderwaterPayment,
} from "@/lib/types";
import { DateRangeForm } from "./date-range-form";
import { CsvExportButton } from "./csv-export-button";

function formatDate(d: string) {
  return new Date(d).toLocaleDateString("en-GH", {
    day: "2-digit",
    month: "short",
    year: "numeric",
  });
}

function formatDateTime(d: string) {
  return new Date(d).toLocaleString("en-GH", {
    day: "2-digit",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function bps(v: number) {
  return `${(v / 100).toFixed(2)}%`;
}

/** Pesewas with an explicit leading sign — for the drift / margin figures
 *  where the direction is the whole point. */
function signedPesewas(v: number) {
  return `${v > 0 ? "+" : v < 0 ? "−" : ""}${formatPesewas(Math.abs(v))}`;
}

function SummaryCard({
  label,
  value,
  sub,
  tone,
}: {
  label: string;
  value: string;
  sub?: string;
  tone?: "loss" | "gain";
}) {
  const valueColor =
    tone === "loss"
      ? "text-red-600"
      : tone === "gain"
        ? "text-green-700"
        : "text-neutral-900";
  return (
    <div className="rounded-lg border border-neutral-200 p-4">
      <div className="text-xs uppercase tracking-wide text-neutral-500">
        {label}
      </div>
      <div className={`mt-1 text-2xl font-semibold ${valueColor}`}>{value}</div>
      {sub && <div className="mt-1 text-xs text-neutral-400">{sub}</div>}
    </div>
  );
}

function firstParam(v: string | string[] | undefined): string | undefined {
  return Array.isArray(v) ? v[0] : v;
}

export default async function ReconciliationPage(
  props: PageProps<"/reconciliation">,
) {
  const searchParams = await props.searchParams;
  const periodStart = firstParam(searchParams.period_start);
  const periodEnd = firstParam(searchParams.period_end);

  let report;
  try {
    report = await getReconciliation({ periodStart, periodEnd });
  } catch (err) {
    if (err instanceof ApiError && err.status === 403) {
      return (
        <p className="text-sm text-neutral-500">
          You don&apos;t have permission to view reconciliation (requires
          reporting.view).
        </p>
      );
    }
    throw err;
  }

  const { summary } = report;
  const marginTone: "loss" | "gain" =
    summary.realized_margin_pesewas < 0 ? "loss" : "gain";
  const driftTone: "loss" | "gain" | undefined =
    summary.psp_fee_drift_pesewas > 0
      ? "loss"
      : summary.psp_fee_drift_pesewas < 0
        ? "gain"
        : undefined;

  return (
    <div className="space-y-6">
      <div>
        <div className="flex items-baseline gap-2">
          <h1 className="text-2xl font-semibold text-neutral-900">
            Margin Reconciliation
          </h1>
          <span className="text-xs font-mono text-neutral-400">
            Section 7.5
          </span>
        </div>
        <p className="max-w-3xl text-sm text-neutral-500">
          Booked commission against the PSP fee Paystack actually charged, and
          the realized margin that leaves, for{" "}
          {formatDate(report.period_start)} – {formatDate(report.period_end)}.
          The revenue dashboard nets a loss-making invoice against a profitable
          merchant; this doesn&apos;t. Per-merchant collection-fee overrides
          aren&apos;t reflected in the expected-cost baseline — it&apos;s a
          model-wide drift check, not a settlement.
        </p>
      </div>

      <div className="flex flex-wrap items-center justify-between gap-3">
        <DateRangeForm
          periodStart={report.period_start}
          periodEnd={report.period_end}
        />
        <CsvExportButton report={report} />
      </div>

      <div className="grid gap-3 sm:grid-cols-3 lg:grid-cols-4">
        <SummaryCard
          label="Realized margin"
          value={signedPesewas(summary.realized_margin_pesewas)}
          sub={`${bps(summary.realized_margin_bps)} of GMV · booked commission − actual PSP fee`}
          tone={marginTone}
        />
        <SummaryCard
          label="Booked commission"
          value={formatPesewas(summary.booked_commission_pesewas)}
          sub={`on ${formatPesewas(summary.gmv_pesewas)} GMV`}
        />
        <SummaryCard
          label="PSP fee — actual"
          value={formatPesewas(summary.psp_fee_actual_pesewas)}
          sub="reported by Paystack per charge"
        />
        <SummaryCard
          label="PSP fee — drift"
          value={signedPesewas(summary.psp_fee_drift_pesewas)}
          sub={`vs. ${formatPesewas(summary.psp_fee_expected_pesewas)} expected at ${bps(summary.expected_collection_fee_bps)}`}
          tone={driftTone}
        />
        <SummaryCard
          label="Underwater merchants"
          value={String(summary.underwater_merchant_count)}
          sub="realized margin below zero this period"
          tone={summary.underwater_merchant_count > 0 ? "loss" : undefined}
        />
        <SummaryCard
          label="Underwater payments"
          value={String(summary.underwater_payment_count)}
          sub="individual charges that cost more than they earned"
          tone={summary.underwater_payment_count > 0 ? "loss" : undefined}
        />
      </div>

      <div>
        <h2 className="mb-2 text-sm font-semibold text-neutral-700">
          By merchant
        </h2>
        {report.merchants.length === 0 ? (
          <p className="text-sm text-neutral-500">
            No successful payments in this period.
          </p>
        ) : (
          <div className="overflow-x-auto rounded-lg border border-neutral-200">
            <table className="w-full text-sm">
              <thead className="bg-neutral-50 text-left text-xs uppercase tracking-wide text-neutral-500">
                <tr>
                  <th className="px-4 py-2">Merchant</th>
                  <th className="px-4 py-2 text-right">GMV</th>
                  <th className="px-4 py-2 text-right">Booked commission</th>
                  <th className="px-4 py-2 text-right">Effective rate</th>
                  <th className="px-4 py-2 text-right">PSP fee</th>
                  <th className="px-4 py-2 text-right">Realized margin</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-neutral-100">
                {report.merchants.map((m: ReconciliationMerchant) => {
                  const underwater = m.realized_margin_pesewas < 0;
                  return (
                    <tr
                      key={m.merchant_id}
                      className={underwater ? "bg-red-50" : "hover:bg-neutral-50"}
                    >
                      <td className="px-4 py-2 font-medium">
                        {m.business_name}
                      </td>
                      <td className="px-4 py-2 text-right tabular-nums">
                        {formatPesewas(m.gmv_pesewas)}
                      </td>
                      <td className="px-4 py-2 text-right tabular-nums text-neutral-600">
                        {formatPesewas(m.booked_commission_pesewas)}
                      </td>
                      <td className="px-4 py-2 text-right tabular-nums text-neutral-600">
                        {bps(m.effective_take_rate_bps)}
                      </td>
                      <td className="px-4 py-2 text-right tabular-nums text-neutral-600">
                        {formatPesewas(m.psp_fee_pesewas)}
                      </td>
                      <td
                        className={`px-4 py-2 text-right font-medium tabular-nums ${
                          underwater ? "text-red-600" : "text-green-700"
                        }`}
                      >
                        {signedPesewas(m.realized_margin_pesewas)}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <div>
        <h2 className="mb-2 text-sm font-semibold text-neutral-700">
          Underwater payments
        </h2>
        {report.underwater.length === 0 ? (
          <p className="text-sm text-neutral-500">
            No payment in this period cost more in PSP fees than the commission
            booked against it.
          </p>
        ) : (
          <>
            <p className="mb-2 max-w-3xl text-xs text-neutral-400">
              Each of these is a single successful charge where Paystack&apos;s
              fee came out above the prorated commission — the shape the
              bundled-delivery leak produced. Worst first, capped at 100.
            </p>
            <div className="overflow-x-auto rounded-lg border border-neutral-200">
              <table className="w-full text-sm">
                <thead className="bg-neutral-50 text-left text-xs uppercase tracking-wide text-neutral-500">
                  <tr>
                    <th className="px-4 py-2">Invoice</th>
                    <th className="px-4 py-2">Merchant</th>
                    <th className="px-4 py-2 text-right">Amount paid</th>
                    <th className="px-4 py-2 text-right">Booked commission</th>
                    <th className="px-4 py-2 text-right">PSP fee</th>
                    <th className="px-4 py-2 text-right">Shortfall</th>
                    <th className="px-4 py-2 text-right">Paid</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-neutral-100">
                  {report.underwater.map((u: UnderwaterPayment) => (
                    <tr key={u.invoice_reference} className="hover:bg-neutral-50">
                      <td className="px-4 py-2 font-mono text-xs text-neutral-600">
                        {u.invoice_reference}
                      </td>
                      <td className="px-4 py-2">{u.business_name}</td>
                      <td className="px-4 py-2 text-right tabular-nums text-neutral-600">
                        {formatPesewas(u.amount_pesewas)}
                      </td>
                      <td className="px-4 py-2 text-right tabular-nums text-neutral-600">
                        {formatPesewas(u.booked_commission_pesewas)}
                      </td>
                      <td className="px-4 py-2 text-right tabular-nums text-neutral-600">
                        {formatPesewas(u.psp_fee_pesewas)}
                      </td>
                      <td className="px-4 py-2 text-right font-medium tabular-nums text-red-600">
                        {"−"}
                        {formatPesewas(u.shortfall_pesewas)}
                      </td>
                      <td className="px-4 py-2 text-right text-xs text-neutral-500">
                        {formatDateTime(u.paid_at)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
