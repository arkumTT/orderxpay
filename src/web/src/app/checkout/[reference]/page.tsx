import { notFound } from "next/navigation";
import { ApiError, apiFetch } from "@/lib/api";
import { formatPesewas } from "@/lib/money";
import type { CheckoutResponse } from "@/lib/types";
import { PaymentPanel } from "./payment-panel";

const TERMINAL_STATUSES = new Set(["expired", "cancelled", "refunded"]);

// Hosted checkout page (Section 5.1): single-purpose, lightweight, no login.
// The reference in the URL is a bearer credential (Section 5.3) — rate
// limiting / expiry enforcement belongs on the API side once built.
export default async function CheckoutPage(
  props: PageProps<"/checkout/[reference]">,
) {
  const { reference } = await props.params;
  const searchParams = await props.searchParams;
  // Paystack appends both `reference` and `trxref` (same value) to the
  // callback_url on redirect back — either is fine to key off of.
  const trxReference = firstParam(
    searchParams.trxref ?? searchParams.reference,
  );

  let data: CheckoutResponse;
  try {
    data = trxReference
      ? await apiFetch<CheckoutResponse>(
          `/api/v1/public/checkout/${reference}/verify?trx_reference=${encodeURIComponent(trxReference)}`,
        )
      : await apiFetch<CheckoutResponse>(
          `/api/v1/public/checkout/${reference}`,
        );
  } catch (err) {
    if (err instanceof ApiError && err.status === 404) notFound();
    throw err;
  }

  const { invoice, line_items, amount_paid_pesewas, amount_owed_pesewas } = data;
  const canPay = !TERMINAL_STATUSES.has(invoice.status) && invoice.status !== "paid";

  return (
    <div className="mx-auto max-w-md px-4 py-8">
      <div className="rounded-xl border border-neutral-200 p-6">
        <p className="text-xs uppercase tracking-wide text-neutral-400">
          Invoice {invoice.reference}
        </p>
        <p className="mt-1 text-sm text-neutral-500 capitalize">
          Status: {invoice.status.replace("_", " ")}
        </p>

        <ul className="mt-6 divide-y divide-neutral-100">
          {line_items.map((item) => (
            <li key={item.id} className="flex justify-between py-2 text-sm">
              <span>
                {item.description} × {item.quantity}
              </span>
              <span>{formatPesewas(item.line_total_pesewas)}</span>
            </li>
          ))}
        </ul>

        <div className="mt-4 space-y-1 border-t border-neutral-200 pt-4 text-sm">
          <div className="flex justify-between text-neutral-500">
            <span>Subtotal</span>
            <span>{formatPesewas(invoice.subtotal_pesewas)}</span>
          </div>
          <div className="flex justify-between text-neutral-500">
            <span>Service charge</span>
            <span>{formatPesewas(invoice.service_charge_pesewas)}</span>
          </div>
          <div className="flex justify-between text-base font-semibold text-neutral-900">
            <span>Total</span>
            <span>{formatPesewas(invoice.total_pesewas)}</span>
          </div>
        </div>

        {invoice.status === "paid" && (
          <div className="mt-6 rounded-lg border border-green-200 bg-green-50 p-4 text-center text-sm font-medium text-green-800">
            Payment received — thank you.
          </div>
        )}

        {invoice.status === "partially_paid" && (
          <p className="mt-6 text-center text-sm text-neutral-500">
            {formatPesewas(amount_paid_pesewas)} received so far — pay the
            remaining {formatPesewas(amount_owed_pesewas)} below.
          </p>
        )}

        {TERMINAL_STATUSES.has(invoice.status) && (
          <div className="mt-6 rounded-lg border border-neutral-200 bg-neutral-50 p-4 text-center text-sm text-neutral-500">
            This invoice is {invoice.status} and can no longer be paid.
          </div>
        )}

        {canPay && (
          <PaymentPanel
            reference={reference}
            amountOwedPesewas={amount_owed_pesewas}
          />
        )}
      </div>
    </div>
  );
}

function firstParam(
  value: string | string[] | undefined,
): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}
