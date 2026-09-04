import { notFound } from "next/navigation";
import { ApiError, apiFetch } from "@/lib/api";
import { formatPesewas } from "@/lib/money";
import type { CheckoutResponse } from "@/lib/types";
import { PaymentPanel } from "./payment-panel";
import { DeliveryHandoff } from "./delivery-handoff";

const TERMINAL_STATUSES = new Set(["expired", "cancelled", "refunded"]);

// Hosted checkout page (Section 5.1): single-purpose, lightweight, no login.
// The reference in the URL is a bearer credential (Section 5.3) — rate
// limiting / expiry enforcement belongs on the API side once built.
//
// Visual design follows the Claude Design handoff (OrderxPay.dc.html,
// gallery screens 6-8 — "Customer Checkout" / "Checkout — Success (Kojo
// rider)" / "Checkout — Success (Bolt Send / arrange)"). That mockup was
// built as a single fixed-state screen per delivery outcome; this page
// derives the same visual states from real invoice/delivery data instead,
// plus two states the mockup doesn't cover — partially-paid and terminal
// (expired/cancelled/refunded) — since this page has to handle every real
// invoice status, not just the two the prototype demonstrates.
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

  const { invoice, line_items, amount_paid_pesewas, amount_owed_pesewas, delivery, merchant } = data;
  const isPaid = invoice.status === "paid";
  const isPartial = invoice.status === "partially_paid";
  const isTerminal = TERMINAL_STATUSES.has(invoice.status);
  const canPay = !isTerminal && !isPaid;
  // The delivery fee only belongs in the invoice total when it's actually
  // bundled into this invoice (the merchant's own rider) — a Bolt Send /
  // third-party fee is set and collected by that provider separately, so
  // it's deliberately not shown as a line item here (Prompt 5/6).
  const hasDeliveryFee =
    invoice.delivery_fee_handling === "bundled" &&
    !!invoice.delivery_fee_pesewas;

  return (
    <div className="min-h-full bg-oxp-app-bg">
      <div className="mx-auto max-w-md">
        <div className="bg-oxp-black px-5 py-[18px]">
          <p className="text-xl font-bold text-white">
            {merchant?.business_name ?? "OrderxPay"}
          </p>
          <p className="mt-1 text-xs text-white/60">Invoice #{invoice.reference}</p>
        </div>

        <div className="flex flex-col gap-4 px-5 py-6">
          <div className="rounded-2xl border border-oxp-border bg-white p-4">
            <div className="flex flex-col gap-2.5">
              {line_items.map((item) => (
                <div
                  key={item.id}
                  className="flex justify-between gap-3 text-[13px] text-oxp-black"
                >
                  <span>
                    {item.description} × {item.quantity}
                  </span>
                  <span className="font-semibold">
                    {formatPesewas(item.line_total_pesewas)}
                  </span>
                </div>
              ))}
            </div>

            <div className="my-2.5 h-px bg-oxp-border" />

            <div className="flex flex-col gap-2.5">
              <div className="flex justify-between text-[13px] text-oxp-muted">
                <span>Service charge</span>
                <span className="font-semibold text-oxp-black">
                  {formatPesewas(invoice.service_charge_pesewas)}
                </span>
              </div>
              {hasDeliveryFee && (
                <div className="flex justify-between text-[13px] text-oxp-muted">
                  <span>
                    Delivery
                    {delivery?.contact_name ? ` (${delivery.contact_name})` : ""}
                  </span>
                  <span className="font-semibold text-oxp-black">
                    {formatPesewas(invoice.delivery_fee_pesewas!)}
                  </span>
                </div>
              )}
            </div>

            <div className="my-2.5 h-px bg-oxp-border" />

            <div className="flex items-center justify-between">
              <span className="text-sm font-bold text-oxp-black">Total due</span>
              <span className="text-2xl font-bold text-oxp-orange">
                {formatPesewas(invoice.total_pesewas)}
              </span>
            </div>
          </div>

          {isPaid && (
            <div className="flex items-center gap-2 rounded-xl border border-oxp-green/30 bg-oxp-green/10 px-4 py-3.5">
              <span className="text-sm font-bold text-oxp-green">
                Payment received ✓
              </span>
            </div>
          )}

          {isPartial && (
            <p className="text-center text-sm text-oxp-muted">
              {formatPesewas(amount_paid_pesewas)} received so far — pay the
              remaining {formatPesewas(amount_owed_pesewas)} below.
            </p>
          )}

          {isTerminal && (
            <div className="rounded-xl border border-oxp-border bg-white p-4 text-center text-sm text-oxp-muted">
              This invoice is {invoice.status} and can no longer be paid.
            </div>
          )}

          {isPaid && delivery && <DeliveryHandoff delivery={delivery} />}

          {canPay && (
            <>
              <PaymentPanel
                reference={reference}
                amountOwedPesewas={amount_owed_pesewas}
              />
              <p className="text-center text-[11px] text-oxp-placeholder">
                Secured by licensed payment partner · No account needed
              </p>
            </>
          )}
        </div>
      </div>
    </div>
  );
}

function firstParam(
  value: string | string[] | undefined,
): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}
