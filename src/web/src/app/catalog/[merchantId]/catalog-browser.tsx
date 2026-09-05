"use client";

import { useState } from "react";
import Image from "next/image";
import { apiFetch } from "@/lib/api";
import { formatPesewas } from "@/lib/money";
import type { Item } from "@/lib/types";

// Customer-initiated ordering (Section 4.6, 12.2): browse, select quantities,
// submit a request — this is a request, not a payable invoice. The merchant
// confirms availability before an invoice is generated.
export function CatalogBrowser({
  merchantId,
  items,
}: {
  merchantId: string;
  items: Item[];
}) {
  const [quantities, setQuantities] = useState<Record<string, number>>({});
  const [customerContact, setCustomerContact] = useState("");
  const [status, setStatus] = useState<
    "idle" | "submitting" | "submitted" | "error"
  >("idle");
  const [error, setError] = useState<string | null>(null);

  const selectedItems = items
    .filter((item) => (quantities[item.id] ?? 0) > 0)
    .map((item) => ({ item, quantity: quantities[item.id] }));

  function adjustQuantity(itemId: string, delta: number) {
    setQuantities((q) => ({
      ...q,
      [itemId]: Math.max(0, (q[itemId] ?? 0) + delta),
    }));
  }

  async function handleSubmit() {
    if (!customerContact || selectedItems.length === 0) return;
    setStatus("submitting");
    setError(null);
    try {
      await apiFetch(`/api/v1/public/merchants/${merchantId}/order-requests`, {
        method: "POST",
        body: JSON.stringify({
          customer_contact: customerContact,
          requested_items: selectedItems.map(({ item, quantity }) => ({
            item_id: item.id,
            name: item.name,
            quantity,
          })),
        }),
      });
      setStatus("submitted");
    } catch (err) {
      setStatus("error");
      setError(err instanceof Error ? err.message : "request failed");
    }
  }

  if (status === "submitted") {
    return (
      <div className="rounded-lg border border-green-200 bg-green-50 p-4 text-sm text-green-800">
        Request sent. The merchant will confirm availability and send you a
        payment link.
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <ul className="divide-y divide-neutral-100 rounded-lg border border-neutral-200">
        {items.map((item) => {
          const quantity = quantities[item.id] ?? 0;
          return (
            <li
              key={item.id}
              className="flex items-center gap-3 px-4 py-3"
            >
              {item.image_url && (
                <Image
                  src={item.image_url}
                  alt={item.name}
                  width={56}
                  height={56}
                  className="h-14 w-14 shrink-0 rounded-xl object-cover"
                />
              )}
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-medium text-neutral-900">
                  {item.name}
                </p>
                <p className="text-sm text-neutral-500">
                  {formatPesewas(item.unit_price_pesewas)}
                  {item.qty_unit ? ` / ${item.qty_unit}` : ""}
                </p>
                {item.availability_status !== "in_stock" && (
                  <p className="text-xs text-amber-600">
                    {item.availability_status.replace("_", " ")}
                  </p>
                )}
              </div>
              <div className="flex shrink-0 items-center gap-2.5">
                <button
                  type="button"
                  onClick={() => adjustQuantity(item.id, -1)}
                  disabled={quantity === 0}
                  aria-label={`Decrease quantity of ${item.name}`}
                  className="flex h-7 w-7 items-center justify-center rounded-full border border-neutral-300 text-base leading-none text-neutral-900 disabled:opacity-40"
                >
                  −
                </button>
                <span className="w-4 text-center text-sm font-semibold text-neutral-900">
                  {quantity}
                </span>
                <button
                  type="button"
                  onClick={() => adjustQuantity(item.id, 1)}
                  aria-label={`Increase quantity of ${item.name}`}
                  className="flex h-7 w-7 items-center justify-center rounded-full bg-neutral-900 text-base leading-none text-white"
                >
                  +
                </button>
              </div>
            </li>
          );
        })}
      </ul>

      <div className="space-y-2">
        <label className="text-sm text-neutral-700" htmlFor="contact">
          Your phone number or WhatsApp
        </label>
        <input
          id="contact"
          type="text"
          value={customerContact}
          onChange={(e) => setCustomerContact(e.target.value)}
          className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm"
          placeholder="+233..."
        />
      </div>

      {error && <p className="text-sm text-red-600">{error}</p>}

      <button
        type="button"
        disabled={
          status === "submitting" ||
          selectedItems.length === 0 ||
          !customerContact
        }
        onClick={handleSubmit}
        className="w-full rounded-md bg-neutral-900 px-3 py-2 text-sm font-medium text-white disabled:opacity-50"
      >
        {status === "submitting" ? "Sending…" : "Request order"}
      </button>
    </div>
  );
}
