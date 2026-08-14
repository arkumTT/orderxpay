"use client";

import { useState } from "react";
import { ApiError, apiFetch } from "@/lib/api";
import { formatPesewas } from "@/lib/money";
import type { InitiatePaymentResponse } from "@/lib/types";

type Method = "momo" | "card";

// Client component: the Pay button needs to redirect the browser to
// Paystack's hosted checkout page (Section 5.1, 9.1), which a Server
// Component can't do.
export function PaymentPanel({
  reference,
  amountOwedPesewas,
}: {
  reference: string;
  amountOwedPesewas: number;
}) {
  const [method, setMethod] = useState<Method>("momo");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function pay() {
    setLoading(true);
    setError(null);
    try {
      const res = await apiFetch<InitiatePaymentResponse>(
        `/api/v1/public/checkout/${reference}/pay`,
        {
          method: "POST",
          body: JSON.stringify({ preferred_method: method }),
        },
      );
      window.location.href = res.authorization_url;
    } catch (err) {
      setError(
        err instanceof ApiError
          ? err.message
          : "Something went wrong. Please try again.",
      );
      setLoading(false);
    }
  }

  return (
    <div className="mt-6">
      <div className="flex gap-2">
        <button
          type="button"
          onClick={() => setMethod("momo")}
          className={`flex-1 rounded-md border px-3 py-2 text-sm font-medium ${
            method === "momo"
              ? "border-neutral-900 bg-neutral-900 text-white"
              : "border-neutral-300 text-neutral-700"
          }`}
        >
          Mobile Money
        </button>
        <button
          type="button"
          onClick={() => setMethod("card")}
          className={`flex-1 rounded-md border px-3 py-2 text-sm font-medium ${
            method === "card"
              ? "border-neutral-900 bg-neutral-900 text-white"
              : "border-neutral-300 text-neutral-700"
          }`}
        >
          Card
        </button>
      </div>

      {error && <p className="mt-3 text-sm text-red-600">{error}</p>}

      <button
        type="button"
        onClick={pay}
        disabled={loading}
        className="mt-4 w-full rounded-md bg-neutral-900 px-3 py-3 text-sm font-semibold text-white disabled:opacity-50"
      >
        {loading
          ? "Redirecting…"
          : `Pay ${formatPesewas(amountOwedPesewas)}`}
      </button>
    </div>
  );
}
