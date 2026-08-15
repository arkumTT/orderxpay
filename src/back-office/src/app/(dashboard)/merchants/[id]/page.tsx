import Link from "next/link";
import { notFound } from "next/navigation";
import {
  getMerchant,
  getMerchantItems,
  getMerchantInvoices,
  getMerchantSettlements,
  getMerchantRiskFlags,
  getMerchantNotes,
} from "@/lib/merchants";
import { formatPesewas } from "@/lib/money";
import { ApiError } from "@/lib/session";
import { MerchantStatusActions } from "./status-actions";
import { MerchantKYCTierActions } from "./kyc-tier-actions";
import { MerchantNotes } from "./merchant-notes";

const ALLOCATION_LABEL: Record<string, string> = {
  customer_only: "Customer pays the service charge",
  merchant_only: "Merchant absorbs the service charge",
  split: "Split between customer and merchant",
};

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

const SETTLEMENT_STATUS_STYLES: Record<string, string> = {
  pending: "bg-amber-100 text-amber-800",
  processing: "bg-blue-100 text-blue-800",
  paid: "bg-green-100 text-green-800",
  failed: "bg-red-100 text-red-800",
};

const RISK_STATUS_STYLES: Record<string, string> = {
  open: "bg-amber-100 text-amber-800",
  dismissed: "bg-neutral-100 text-neutral-600",
  escalated: "bg-red-100 text-red-800",
};

function formatDate(d: string) {
  return new Date(d).toLocaleDateString("en-GH", {
    day: "2-digit",
    month: "short",
    year: "numeric",
  });
}

export default async function MerchantDetailPage(
  props: PageProps<"/merchants/[id]">,
) {
  const { id } = await props.params;

  let merchant, items, invoices, settlements, riskFlags, notes;
  try {
    [merchant, items, invoices, settlements, riskFlags, notes] =
      await Promise.all([
        getMerchant(id),
        getMerchantItems(id),
        getMerchantInvoices(id),
        getMerchantSettlements(id),
        getMerchantRiskFlags(id),
        getMerchantNotes(id),
      ]);
  } catch (err) {
    if (err instanceof ApiError && err.status === 404) notFound();
    if (err instanceof ApiError && err.status === 403) {
      return (
        <p className="text-sm text-neutral-500">
          You don&apos;t have permission to view this merchant (requires
          merchants.view).
        </p>
      );
    }
    throw err;
  }

  return (
    <div className="max-w-3xl space-y-6">
      <div>
        <div className="flex items-baseline gap-2">
          <h1 className="text-2xl font-semibold text-neutral-900">{merchant.business_name}</h1>
          <span className="text-xs font-mono text-neutral-400">Section 7.1</span>
        </div>
        {merchant.category && <p className="text-sm text-neutral-500">{merchant.category}</p>}
      </div>

      <dl className="grid grid-cols-2 gap-4 rounded-lg border border-neutral-200 p-4 text-sm sm:grid-cols-3">
        <div>
          <dt className="text-neutral-400">Status</dt>
          <dd>
            <span
              className={`rounded-full px-2 py-0.5 text-xs font-medium capitalize ${MERCHANT_STATUS_STYLES[merchant.status] ?? "bg-neutral-100 text-neutral-600"}`}
            >
              {merchant.status}
            </span>
          </dd>
        </div>
        <div>
          <dt className="text-neutral-400">KYC Tier</dt>
          <dd className="font-medium text-neutral-900">Tier {merchant.kyc_tier}</dd>
        </div>
        <div>
          <dt className="text-neutral-400">Phone</dt>
          <dd className="font-medium text-neutral-900">{merchant.phone}</dd>
        </div>
        <div>
          <dt className="text-neutral-400">Payout schedule</dt>
          <dd className="font-medium text-neutral-900 capitalize">{merchant.payout_schedule.replace("_", " ")}</dd>
        </div>
        <div>
          <dt className="text-neutral-400">Payout min. threshold</dt>
          <dd className="font-medium text-neutral-900">{formatPesewas(merchant.payout_min_threshold_pesewas)}</dd>
        </div>
        <div>
          <dt className="text-neutral-400">Joined</dt>
          <dd className="font-medium text-neutral-900">{formatDate(merchant.created_at)}</dd>
        </div>
      </dl>

      <div className="rounded-lg border border-neutral-200 p-4 text-sm">
        <h2 className="mb-1 font-medium text-neutral-900">Fee allocation</h2>
        <p className="text-neutral-600">
          {ALLOCATION_LABEL[merchant.service_charge_allocation]}
          {merchant.service_charge_allocation === "split" && merchant.service_charge_split_bps != null
            ? ` — customer pays ${(merchant.service_charge_split_bps / 100).toFixed(1)}% of the commission`
            : ""}
        </p>
      </div>

      <div className="rounded-lg border border-neutral-200 p-4">
        <h2 className="mb-2 text-sm font-semibold text-neutral-700">Status (merchants.manage_status)</h2>
        <MerchantStatusActions merchantId={merchant.id} status={merchant.status} />
      </div>

      <div className="rounded-lg border border-neutral-200 p-4">
        <h2 className="mb-2 text-sm font-semibold text-neutral-700">KYC tier (merchants.kyc_review)</h2>
        <MerchantKYCTierActions merchantId={merchant.id} kycTier={merchant.kyc_tier} />
      </div>

      <div>
        <h2 className="mb-2 text-sm font-semibold text-neutral-700">
          Catalog snapshot ({items.length})
        </h2>
        {items.length === 0 ? (
          <p className="text-sm text-neutral-500">No active items.</p>
        ) : (
          <div className="overflow-x-auto rounded-lg border border-neutral-200">
            <table className="w-full text-sm">
              <thead className="bg-neutral-50 text-left text-xs uppercase tracking-wide text-neutral-500">
                <tr>
                  <th className="px-4 py-2">Name</th>
                  <th className="px-4 py-2 text-right">Price</th>
                  <th className="px-4 py-2">Availability</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-neutral-100">
                {items.map((it) => (
                  <tr key={it.id}>
                    <td className="px-4 py-2 text-neutral-900">
                      {it.name}
                      {it.qty_unit && (
                        <span className="ml-1 text-xs text-neutral-400">/ {it.qty_unit}</span>
                      )}
                    </td>
                    <td className="px-4 py-2 text-right text-neutral-600">
                      {formatPesewas(it.unit_price_pesewas)}
                    </td>
                    <td className="px-4 py-2 text-neutral-600 capitalize">
                      {it.availability_status.replace("_", " ")}
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
          Transaction history ({invoices.length})
        </h2>
        {invoices.length === 0 ? (
          <p className="text-sm text-neutral-500">No invoices yet.</p>
        ) : (
          <div className="overflow-x-auto rounded-lg border border-neutral-200">
            <table className="w-full text-sm">
              <thead className="bg-neutral-50 text-left text-xs uppercase tracking-wide text-neutral-500">
                <tr>
                  <th className="px-4 py-2">Reference</th>
                  <th className="px-4 py-2">Customer</th>
                  <th className="px-4 py-2 text-right">Total</th>
                  <th className="px-4 py-2">Status</th>
                  <th className="px-4 py-2">Created</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-neutral-100">
                {invoices.map((inv) => (
                  <tr key={inv.id}>
                    <td className="px-4 py-2">
                      <Link
                        href={`/support/${inv.reference}`}
                        className="font-mono text-xs text-neutral-900 underline"
                      >
                        {inv.reference}
                      </Link>
                    </td>
                    <td className="px-4 py-2 text-neutral-600">{inv.customer_contact}</td>
                    <td className="px-4 py-2 text-right text-neutral-900">
                      {formatPesewas(inv.total_pesewas)}
                    </td>
                    <td className="px-4 py-2">
                      <span
                        className={`rounded-full px-2 py-0.5 text-xs font-medium ${INVOICE_STATUS_STYLES[inv.status] ?? "bg-neutral-100 text-neutral-600"}`}
                      >
                        {inv.status.replace("_", " ")}
                      </span>
                    </td>
                    <td className="px-4 py-2 text-neutral-500">{formatDate(inv.created_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <div>
        <h2 className="mb-2 text-sm font-semibold text-neutral-700">
          Payout history ({settlements.length})
        </h2>
        {settlements.length === 0 ? (
          <p className="text-sm text-neutral-500">No settlements generated yet.</p>
        ) : (
          <div className="overflow-x-auto rounded-lg border border-neutral-200">
            <table className="w-full text-sm">
              <thead className="bg-neutral-50 text-left text-xs uppercase tracking-wide text-neutral-500">
                <tr>
                  <th className="px-4 py-2">Period</th>
                  <th className="px-4 py-2 text-right">Net payout</th>
                  <th className="px-4 py-2">Status</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-neutral-100">
                {settlements.map((s) => (
                  <tr key={s.id}>
                    <td className="px-4 py-2 text-neutral-600">
                      {formatDate(s.period_start)} – {formatDate(s.period_end)}
                    </td>
                    <td className="px-4 py-2 text-right text-neutral-900">
                      {formatPesewas(s.net_payout_pesewas)}
                    </td>
                    <td className="px-4 py-2">
                      <span
                        className={`rounded-full px-2 py-0.5 text-xs font-medium ${SETTLEMENT_STATUS_STYLES[s.status]}`}
                      >
                        {s.status}
                      </span>
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
          Risk flags ({riskFlags.length})
        </h2>
        {riskFlags.length === 0 ? (
          <p className="text-sm text-neutral-500">No risk flags for this merchant.</p>
        ) : (
          <ul className="space-y-2">
            {riskFlags.map((f) => (
              <li key={f.id} className="rounded-md border border-neutral-200 p-3 text-sm">
                <div className="flex items-center justify-between gap-2">
                  <span className="font-medium text-neutral-900 capitalize">
                    {f.flag_type.replace("_", " ")}
                  </span>
                  <span
                    className={`rounded-full px-2 py-0.5 text-xs font-medium ${RISK_STATUS_STYLES[f.status]}`}
                  >
                    {f.status}
                  </span>
                </div>
                <p className="mt-1 text-neutral-600">{f.details}</p>
                <p className="mt-1 text-xs text-neutral-400">
                  {formatDate(f.created_at)} ·{" "}
                  <Link href="/risk" className="underline">
                    manage in Risk &amp; Fraud
                  </Link>
                </p>
              </li>
            ))}
          </ul>
        )}
      </div>

      <div>
        <h2 className="mb-2 text-sm font-semibold text-neutral-700">Notes</h2>
        <MerchantNotes merchantId={merchant.id} notes={notes} />
      </div>
    </div>
  );
}
