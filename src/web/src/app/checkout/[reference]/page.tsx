import { notFound } from "next/navigation";
import { ApiError, apiFetch } from "@/lib/api";
import { formatPesewas } from "@/lib/money";
import type { CheckoutResponse } from "@/lib/types";

// Hosted checkout page (Section 5.1): single-purpose, lightweight, no login.
// The reference in the URL is a bearer credential (Section 5.3) — rate
// limiting / expiry enforcement belongs on the API side once built.
export default async function CheckoutPage(
  props: PageProps<"/checkout/[reference]">,
) {
  const { reference } = await props.params;

  let data: CheckoutResponse;
  try {
    data = await apiFetch<CheckoutResponse>(
      `/api/v1/public/checkout/${reference}`,
    );
  } catch (err) {
    if (err instanceof ApiError && err.status === 404) notFound();
    throw err;
  }

  const { invoice, line_items } = data;

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

        {/* TODO: Mobile Money / card payment method tabs via the PSP's
            hosted fields or redirect (Section 5.1, 9.1) — not yet wired,
            payment collection depends on PSP selection. */}
        <div className="mt-6 rounded-lg border border-dashed border-neutral-300 p-4 text-center text-sm text-neutral-400">
          Payment methods not yet implemented — depends on PSP selection
          (Section 9.1).
        </div>
      </div>
    </div>
  );
}
