import Link from "next/link";
import { searchSupport } from "@/lib/support";
import { ApiError } from "@/lib/session";
import { formatPesewas } from "@/lib/money";
import { SupportSearchBox } from "./search-box";

const MERCHANT_STATUS_STYLES: Record<string, string> = {
  active: "bg-green-100 text-green-800",
  pending: "bg-amber-100 text-amber-800",
  restricted: "bg-orange-100 text-orange-800",
  suspended: "bg-red-100 text-red-800",
};

const INVOICE_STATUS_STYLES: Record<string, string> = {
  sent: "bg-neutral-100 text-neutral-600",
  viewed: "bg-blue-100 text-blue-800",
  partially_paid: "bg-amber-100 text-amber-800",
  paid: "bg-green-100 text-green-800",
  expired: "bg-neutral-100 text-neutral-500",
  cancelled: "bg-neutral-100 text-neutral-500",
  refunded: "bg-purple-100 text-purple-800",
};

function formatDate(d: string) {
  return new Date(d).toLocaleDateString("en-GH", {
    day: "2-digit",
    month: "short",
    year: "numeric",
  });
}

function firstParam(v: string | string[] | undefined): string | undefined {
  return Array.isArray(v) ? v[0] : v;
}

export default async function SupportPage(props: PageProps<"/support">) {
  const searchParams = await props.searchParams;
  const q = firstParam(searchParams.q) ?? "";

  let results;
  let searchError: string | null = null;
  if (q.trim().length >= 2) {
    try {
      results = await searchSupport(q.trim());
    } catch (err) {
      if (err instanceof ApiError && err.status === 403) {
        return (
          <p className="text-sm text-neutral-500">
            You don&apos;t have permission to use the support console
            (requires support.view).
          </p>
        );
      }
      searchError = "Search failed — try again.";
    }
  }

  return (
    <div className="space-y-6">
      <div>
        <div className="flex items-baseline gap-2">
          <h1 className="text-2xl font-semibold text-neutral-900">
            Support / Helpdesk Console
          </h1>
          <span className="text-xs font-mono text-neutral-400">
            Section 7.10
          </span>
        </div>
        <p className="text-sm text-neutral-500">
          Look up a merchant or a customer&apos;s transaction without raw
          database access. Read-only — the Support role has no mutation
          permissions; anything that needs a change (refund, status
          override, KYC decision) has to go through the merchant/disputes/
          risk pages, gated separately.
        </p>
      </div>

      <SupportSearchBox query={q} />

      {searchError && <p className="text-sm text-red-600">{searchError}</p>}

      {!results && !searchError && (
        <p className="text-sm text-neutral-500">
          Search by invoice reference, customer phone, or merchant name/
          phone.
        </p>
      )}

      {results && (
        <>
          <div>
            <h2 className="mb-2 text-sm font-semibold text-neutral-700">
              Transactions ({results.invoices.length})
            </h2>
            {results.invoices.length === 0 ? (
              <p className="text-sm text-neutral-500">No matching transactions.</p>
            ) : (
              <div className="overflow-x-auto rounded-lg border border-neutral-200">
                <table className="w-full text-sm">
                  <thead className="bg-neutral-50 text-left text-xs uppercase tracking-wide text-neutral-500">
                    <tr>
                      <th className="px-4 py-2">Reference</th>
                      <th className="px-4 py-2">Merchant</th>
                      <th className="px-4 py-2">Customer</th>
                      <th className="px-4 py-2 text-right">Total</th>
                      <th className="px-4 py-2">Status</th>
                      <th className="px-4 py-2">Created</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-neutral-100">
                    {results.invoices.map((inv) => (
                      <tr key={inv.id} className="hover:bg-neutral-50">
                        <td className="px-4 py-2">
                          <Link
                            href={`/support/${inv.reference}`}
                            className="font-mono text-xs text-neutral-900 underline"
                          >
                            {inv.reference}
                          </Link>
                        </td>
                        <td className="px-4 py-2 text-neutral-700">
                          {inv.merchant_business_name}
                        </td>
                        <td className="px-4 py-2 text-neutral-600">
                          {inv.customer_contact}
                        </td>
                        <td className="px-4 py-2 text-right text-neutral-900">
                          {formatPesewas(inv.total_pesewas)}
                        </td>
                        <td className="px-4 py-2">
                          <span
                            className={`rounded-full px-2 py-0.5 text-xs font-medium ${
                              INVOICE_STATUS_STYLES[inv.status] ??
                              "bg-neutral-100 text-neutral-600"
                            }`}
                          >
                            {inv.status.replace("_", " ")}
                          </span>
                        </td>
                        <td className="px-4 py-2 text-neutral-500">
                          {formatDate(inv.created_at)}
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
              Merchants ({results.merchants.length})
            </h2>
            {results.merchants.length === 0 ? (
              <p className="text-sm text-neutral-500">No matching merchants.</p>
            ) : (
              <div className="overflow-x-auto rounded-lg border border-neutral-200">
                <table className="w-full text-sm">
                  <thead className="bg-neutral-50 text-left text-xs uppercase tracking-wide text-neutral-500">
                    <tr>
                      <th className="px-4 py-2">Business</th>
                      <th className="px-4 py-2">Phone</th>
                      <th className="px-4 py-2">KYC Tier</th>
                      <th className="px-4 py-2">Status</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-neutral-100">
                    {results.merchants.map((m) => (
                      <tr key={m.id} className="hover:bg-neutral-50">
                        <td className="px-4 py-2">
                          <Link
                            href={`/merchants/${m.id}`}
                            className="font-medium text-neutral-900 underline"
                          >
                            {m.business_name}
                          </Link>
                        </td>
                        <td className="px-4 py-2 text-neutral-600">
                          {m.phone}
                        </td>
                        <td className="px-4 py-2 text-neutral-600">
                          Tier {m.kyc_tier}
                        </td>
                        <td className="px-4 py-2">
                          <span
                            className={`rounded-full px-2 py-0.5 text-xs font-medium ${
                              MERCHANT_STATUS_STYLES[m.status] ??
                              "bg-neutral-100 text-neutral-600"
                            }`}
                          >
                            {m.status}
                          </span>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </>
      )}
    </div>
  );
}
