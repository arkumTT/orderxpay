import Link from "next/link";
import { notFound } from "next/navigation";
import { getSupportTransaction } from "@/lib/support";
import { ApiError } from "@/lib/session";
import { formatPesewas } from "@/lib/money";
import { CopyLinkButton } from "./copy-link-button";

function formatDateTime(d: string) {
  return new Date(d).toLocaleString("en-GH", {
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

const PAYMENT_STATUS_STYLES: Record<string, string> = {
  pending: "bg-amber-100 text-amber-800",
  success: "bg-green-100 text-green-800",
  failed: "bg-red-100 text-red-800",
};

export default async function SupportTransactionPage(
  props: PageProps<"/support/[reference]">,
) {
  const { reference } = await props.params;

  let data;
  try {
    data = await getSupportTransaction(reference);
  } catch (err) {
    if (err instanceof ApiError && err.status === 404) notFound();
    if (err instanceof ApiError && err.status === 403) {
      return (
        <p className="text-sm text-neutral-500">
          You don&apos;t have permission to use the support console
          (requires support.view).
        </p>
      );
    }
    throw err;
  }

  const { invoice, line_items, payments, checkout_url } = data;

  return (
    <div className="max-w-2xl space-y-6">
      <div>
        <Link href="/support" className="text-xs text-neutral-400 hover:underline">
          ← Back to search
        </Link>
        <div className="mt-1 flex items-baseline gap-2">
          <h1 className="font-mono text-xl font-semibold text-neutral-900">
            {invoice.reference}
          </h1>
          <span className="text-xs font-mono text-neutral-400">
            Section 7.10
          </span>
        </div>
        <p className="text-sm text-neutral-500">
          <Link
            href={`/merchants/${invoice.merchant_id}`}
            className="underline"
          >
            {invoice.merchant_business_name}
          </Link>{" "}
          ({invoice.merchant_phone}) · customer {invoice.customer_contact}
        </p>
      </div>

      <dl className="grid grid-cols-2 gap-4 rounded-lg border border-neutral-200 p-4 text-sm sm:grid-cols-3">
        <div>
          <dt className="text-neutral-400">Status</dt>
          <dd className="font-medium capitalize text-neutral-900">
            {invoice.status.replace("_", " ")}
          </dd>
        </div>
        <div>
          <dt className="text-neutral-400">Total</dt>
          <dd className="font-medium text-neutral-900">
            {formatPesewas(invoice.total_pesewas)}
          </dd>
        </div>
        <div>
          <dt className="text-neutral-400">Created</dt>
          <dd className="font-medium text-neutral-900">
            {formatDateTime(invoice.created_at)}
          </dd>
        </div>
        {invoice.delivery_address && (
          <div className="col-span-2 sm:col-span-3">
            <dt className="text-neutral-400">Delivery address</dt>
            <dd className="font-medium text-neutral-900">
              {invoice.delivery_address}
            </dd>
          </div>
        )}
      </dl>

      {checkout_url && (
        <div className="rounded-lg border border-neutral-200 p-4">
          <h2 className="mb-1 text-sm font-semibold text-neutral-700">
            Payment link
          </h2>
          <p className="mb-2 text-xs text-neutral-500">
            No SMS/WhatsApp send integration exists to deliver this
            automatically — copy it and relay it to the customer yourself.
          </p>
          <CopyLinkButton url={checkout_url} />
        </div>
      )}

      <div>
        <h2 className="mb-2 text-sm font-semibold text-neutral-700">Items</h2>
        <div className="overflow-x-auto rounded-lg border border-neutral-200">
          <table className="w-full text-sm">
            <thead className="bg-neutral-50 text-left text-xs uppercase tracking-wide text-neutral-500">
              <tr>
                <th className="px-4 py-2">Description</th>
                <th className="px-4 py-2 text-right">Qty</th>
                <th className="px-4 py-2 text-right">Unit price</th>
                <th className="px-4 py-2 text-right">Line total</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-neutral-100">
              {line_items.map((li) => (
                <tr key={li.id}>
                  <td className="px-4 py-2 text-neutral-900">
                    {li.description}
                  </td>
                  <td className="px-4 py-2 text-right text-neutral-600">
                    {li.quantity}
                  </td>
                  <td className="px-4 py-2 text-right text-neutral-600">
                    {formatPesewas(li.unit_price_pesewas)}
                  </td>
                  <td className="px-4 py-2 text-right text-neutral-900">
                    {formatPesewas(li.line_total_pesewas)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      <div>
        <h2 className="mb-2 text-sm font-semibold text-neutral-700">
          Payment attempts
        </h2>
        {payments.length === 0 ? (
          <p className="text-sm text-neutral-500">
            No payment attempts recorded yet.
          </p>
        ) : (
          <div className="overflow-x-auto rounded-lg border border-neutral-200">
            <table className="w-full text-sm">
              <thead className="bg-neutral-50 text-left text-xs uppercase tracking-wide text-neutral-500">
                <tr>
                  <th className="px-4 py-2">Reference</th>
                  <th className="px-4 py-2">Method</th>
                  <th className="px-4 py-2 text-right">Amount</th>
                  <th className="px-4 py-2">Status</th>
                  <th className="px-4 py-2">Paid at</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-neutral-100">
                {payments.map((p) => (
                  <tr key={p.id}>
                    <td className="px-4 py-2 font-mono text-xs text-neutral-500">
                      {p.psp_reference}
                    </td>
                    <td className="px-4 py-2 uppercase text-neutral-600">
                      {p.method}
                    </td>
                    <td className="px-4 py-2 text-right text-neutral-900">
                      {formatPesewas(p.amount_pesewas)}
                      {p.refunded_amount_pesewas > 0 && (
                        <span className="ml-1 text-xs text-red-600">
                          (-{formatPesewas(p.refunded_amount_pesewas)} refunded)
                        </span>
                      )}
                    </td>
                    <td className="px-4 py-2">
                      <span
                        className={`rounded-full px-2 py-0.5 text-xs font-medium ${
                          PAYMENT_STATUS_STYLES[p.status] ??
                          "bg-neutral-100 text-neutral-600"
                        }`}
                      >
                        {p.status}
                      </span>
                    </td>
                    <td className="px-4 py-2 text-neutral-500">
                      {p.paid_at ? formatDateTime(p.paid_at) : "—"}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <div className="rounded-lg border border-dashed border-neutral-300 p-4 text-xs text-neutral-500">
        Opening a dispute, issuing a refund, or overriding merchant/KYC
        status all require permissions the Support role doesn&apos;t have —
        pass this reference (<span className="font-mono">{invoice.reference}</span>)
        to a Back Office user with the relevant permission instead.
      </div>
    </div>
  );
}
