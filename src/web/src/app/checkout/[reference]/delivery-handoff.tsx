import { formatPesewas } from "@/lib/money";
import type { DeliveryHandoff as DeliveryHandoffData } from "@/lib/types";

// Section 4.11/5.1, Prompt 6: shown once an invoice is paid — either a
// "Call rider" card (the merchant's own contact, Tier 1) or a deep-link
// hand-off card into a verified third-party app (Tier 2). OrderxPay never
// becomes a party to the delivery itself (Section 2.1's non-custodial
// posture) — this is a pointer, not a booking.
export function DeliveryHandoff({ delivery }: { delivery: DeliveryHandoffData }) {
  if (delivery.type === "own_contact") {
    return (
      <div className="mt-6 rounded-lg border border-neutral-200 p-4">
        <p className="text-sm font-semibold text-neutral-900">
          Your delivery
        </p>
        <p className="mt-1 text-sm text-neutral-600">
          {delivery.contact_name ?? "Merchant's rider"}
          {delivery.service_zone ? ` — ${delivery.service_zone}` : ""}
        </p>
        {delivery.flat_fee_pesewas != null && (
          <p className="mt-1 text-xs text-neutral-500">
            Delivery fee: {formatPesewas(delivery.flat_fee_pesewas)}
          </p>
        )}
        {delivery.contact_phone && (
          <a
            href={`tel:${delivery.contact_phone}`}
            className="mt-3 block w-full rounded-md bg-neutral-900 px-4 py-2.5 text-center text-sm font-medium text-white"
          >
            Call rider
          </a>
        )}
      </div>
    );
  }

  const link = delivery.deep_link_template
    ? buildDeepLink(
        delivery.deep_link_template,
        delivery.merchant_business_name ?? "",
        delivery.delivery_address ?? "",
      )
    : null;

  return (
    <div className="mt-6 rounded-lg border border-neutral-200 p-4">
      <p className="text-sm font-semibold text-neutral-900">Your delivery</p>
      <p className="mt-1 text-sm text-neutral-600">
        Hand off to {delivery.contact_name ?? "your delivery provider"} to
        get this order moving.
      </p>
      {link && (
        <a
          href={link}
          target="_blank"
          rel="noopener noreferrer"
          className="mt-3 block w-full rounded-md bg-neutral-900 px-4 py-2.5 text-center text-sm font-medium text-white"
        >
          Get it delivered with {delivery.contact_name}
        </a>
      )}
    </div>
  );
}

function buildDeepLink(template: string, pickup: string, dropoff: string): string {
  return template
    .replace("{pickup}", encodeURIComponent(pickup))
    .replace("{dropoff}", encodeURIComponent(dropoff));
}
