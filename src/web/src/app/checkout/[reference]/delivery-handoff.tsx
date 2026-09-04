import type { DeliveryHandoff as DeliveryHandoffData } from "@/lib/types";

// Section 4.11/5.1, Prompt 6: shown once an invoice is paid — either a
// "Call rider" card (the merchant's own contact, Tier 1) or a deep-link
// hand-off card into a verified third-party app (Tier 2). OrderxPay never
// becomes a party to the delivery itself (Section 2.1's non-custodial
// posture) — this is a pointer, not a booking.
export function DeliveryHandoff({ delivery }: { delivery: DeliveryHandoffData }) {
  if (delivery.type === "own_contact") {
    return (
      <div className="rounded-2xl border border-oxp-border bg-white p-4">
        <p className="text-sm font-bold text-oxp-black">
          Your order is on its way
        </p>
        <div className="mt-3 flex items-center gap-3">
          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-neutral-100 text-sm font-bold text-oxp-black">
            {initial(delivery.contact_name)}
          </div>
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-semibold text-oxp-black">
              {delivery.contact_name ?? "Merchant's rider"}
            </p>
            {delivery.delivery_address && (
              <p className="truncate text-xs text-oxp-muted">
                On the way to {delivery.delivery_address}
              </p>
            )}
          </div>
        </div>
        {delivery.contact_phone && (
          <a
            href={`tel:${delivery.contact_phone}`}
            className="mt-3 flex h-11 w-full items-center justify-center rounded-xl border-[1.5px] border-oxp-black text-sm font-bold text-oxp-black"
          >
            Call rider
          </a>
        )}
      </div>
    );
  }

  // pickup_address is a real address when the merchant has a location on
  // file; merchant_business_name (a name, not an address) is only a
  // fallback for merchants who haven't set one yet.
  const pickup = delivery.pickup_address ?? delivery.merchant_business_name ?? "";
  const link = delivery.deep_link_template
    ? buildDeepLink(delivery.deep_link_template, {
        pickup,
        dropoff: delivery.delivery_address ?? "",
        pickupLat: delivery.pickup_lat ?? null,
        pickupLng: delivery.pickup_lng ?? null,
      })
    : null;

  return (
    <div className="rounded-2xl border border-oxp-border bg-white p-4">
      <p className="text-sm font-bold text-oxp-black">Now book your delivery</p>
      <p className="mt-1 text-xs leading-relaxed text-oxp-muted">
        Opens {delivery.contact_name ?? "your delivery provider"} with{" "}
        {delivery.merchant_business_name ?? "the merchant"}&apos;s pickup
        address and your delivery address pre-filled.
      </p>
      {link ? (
        <>
          <a
            href={link}
            target="_blank"
            rel="noopener noreferrer"
            className="mt-3 flex h-12 w-full items-center justify-center rounded-xl bg-oxp-orange text-sm font-bold text-white"
          >
            Get it delivered with {delivery.contact_name}
          </a>
          <p className="mt-2 text-center text-[10px] text-oxp-placeholder">
            ↗ Leaves OrderxPay for the {delivery.contact_name} app
          </p>
        </>
      ) : (
        <p className="mt-3 text-xs text-oxp-muted">
          Contact {delivery.merchant_business_name ?? "the merchant"} to
          coordinate delivery.
        </p>
      )}
    </div>
  );
}

function initial(name: string | null): string {
  return (name ?? "?").trim().charAt(0).toUpperCase() || "?";
}

function buildDeepLink(
  template: string,
  opts: {
    pickup: string;
    dropoff: string;
    pickupLat: number | null;
    pickupLng: number | null;
  },
): string {
  return template
    .replace("{pickup}", encodeURIComponent(opts.pickup))
    .replace("{dropoff}", encodeURIComponent(opts.dropoff))
    .replace("{pickup_lat}", opts.pickupLat != null ? String(opts.pickupLat) : "")
    .replace("{pickup_lng}", opts.pickupLng != null ? String(opts.pickupLng) : "");
}
