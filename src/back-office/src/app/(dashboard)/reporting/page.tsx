import { getReporting } from "@/lib/reporting";
import { ApiError } from "@/lib/session";
import { formatPesewas } from "@/lib/money";
import { DateRangeForm } from "./date-range-form";
import { CsvExportButton } from "./csv-export-button";

function formatDate(d: string) {
  return new Date(d).toLocaleDateString("en-GH", {
    day: "2-digit",
    month: "short",
    year: "numeric",
  });
}

function SummaryCard({
  label,
  value,
  sub,
}: {
  label: string;
  value: string;
  sub?: string;
}) {
  return (
    <div className="rounded-lg border border-neutral-200 p-4">
      <div className="text-xs uppercase tracking-wide text-neutral-500">
        {label}
      </div>
      <div className="mt-1 text-2xl font-semibold text-neutral-900">
        {value}
      </div>
      {sub && <div className="mt-1 text-xs text-neutral-400">{sub}</div>}
    </div>
  );
}

function firstParam(v: string | string[] | undefined): string | undefined {
  return Array.isArray(v) ? v[0] : v;
}

export default async function ReportingPage(props: PageProps<"/reporting">) {
  const searchParams = await props.searchParams;
  const periodStart = firstParam(searchParams.period_start);
  const periodEnd = firstParam(searchParams.period_end);

  let report;
  try {
    report = await getReporting({ periodStart, periodEnd });
  } catch (err) {
    if (err instanceof ApiError && err.status === 403) {
      return (
        <p className="text-sm text-neutral-500">
          You don&apos;t have permission to view reporting (requires
          reporting.view).
        </p>
      );
    }
    throw err;
  }

  const { summary } = report;

  return (
    <div className="space-y-6">
      <div>
        <div className="flex items-baseline gap-2">
          <h1 className="text-2xl font-semibold text-neutral-900">
            Revenue &amp; Commission Dashboard
          </h1>
          <span className="text-xs font-mono text-neutral-400">
            Section 7.5
          </span>
        </div>
        <p className="text-sm text-neutral-500">
          Commission revenue, GMV, active vs. dormant merchants, and blended
          take-rate for {formatDate(report.period_start)} –{" "}
          {formatDate(report.period_end)}. Net margin nets out PSP fees only
          — WhatsApp/SMS costs aren&apos;t tracked since no messaging
          provider is integrated yet.
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
        <SummaryCard label="GMV" value={formatPesewas(summary.gmv_pesewas)} />
        <SummaryCard
          label="Commission revenue"
          value={formatPesewas(summary.commission_pesewas)}
        />
        <SummaryCard
          label="PSP fees"
          value={formatPesewas(summary.psp_fees_pesewas)}
        />
        <SummaryCard
          label="Net margin"
          value={formatPesewas(summary.net_margin_pesewas)}
          sub="Commission − PSP fees"
        />
        <SummaryCard
          label="Blended take-rate"
          value={`${(summary.blended_take_rate_bps / 100).toFixed(2)}%`}
        />
        <SummaryCard
          label="Active merchants"
          value={String(summary.active_merchants)}
          sub={`of ${summary.total_merchants} total`}
        />
        <SummaryCard
          label="Dormant merchants"
          value={String(summary.dormant_merchants)}
          sub="No activity this period"
        />
      </div>

      <div>
        <h2 className="mb-2 text-sm font-semibold text-neutral-700">
          Daily
        </h2>
        {report.daily.length === 0 ? (
          <p className="text-sm text-neutral-500">
            No successful payments in this period.
          </p>
        ) : (
          <div className="overflow-x-auto rounded-lg border border-neutral-200">
            <table className="w-full text-sm">
              <thead className="bg-neutral-50 text-left text-xs uppercase tracking-wide text-neutral-500">
                <tr>
                  <th className="px-4 py-2">Date</th>
                  <th className="px-4 py-2 text-right">GMV</th>
                  <th className="px-4 py-2 text-right">Commission</th>
                  <th className="px-4 py-2 text-right">PSP fees</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-neutral-100">
                {report.daily.map((d) => (
                  <tr key={d.day} className="hover:bg-neutral-50">
                    <td className="px-4 py-2 text-neutral-900">
                      {formatDate(d.day)}
                    </td>
                    <td className="px-4 py-2 text-right text-neutral-600">
                      {formatPesewas(d.gmv_pesewas)}
                    </td>
                    <td className="px-4 py-2 text-right text-neutral-600">
                      {formatPesewas(d.commission_pesewas)}
                    </td>
                    <td className="px-4 py-2 text-right text-neutral-600">
                      {formatPesewas(d.psp_fees_pesewas)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <div>
        <h2 className="mb-2 text-sm font-semibold text-neutral-700">
          By merchant
        </h2>
        <div className="overflow-x-auto rounded-lg border border-neutral-200">
          <table className="w-full text-sm">
            <thead className="bg-neutral-50 text-left text-xs uppercase tracking-wide text-neutral-500">
              <tr>
                <th className="px-4 py-2">Merchant</th>
                <th className="px-4 py-2 text-right">GMV</th>
                <th className="px-4 py-2 text-right">Commission</th>
                <th className="px-4 py-2 text-right">PSP fees</th>
                <th className="px-4 py-2 text-right">Payments</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-neutral-100">
              {report.merchants.map((m) => (
                <tr
                  key={m.merchant_id}
                  className={`hover:bg-neutral-50 ${m.payment_count === 0 ? "text-neutral-400" : ""}`}
                >
                  <td className="px-4 py-2 font-medium">
                    {m.business_name}
                  </td>
                  <td className="px-4 py-2 text-right">
                    {formatPesewas(m.gmv_pesewas)}
                  </td>
                  <td className="px-4 py-2 text-right">
                    {formatPesewas(m.commission_pesewas)}
                  </td>
                  <td className="px-4 py-2 text-right">
                    {formatPesewas(m.psp_fees_pesewas)}
                  </td>
                  <td className="px-4 py-2 text-right">{m.payment_count}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
