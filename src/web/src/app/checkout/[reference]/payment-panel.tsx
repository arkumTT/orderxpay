"use client";

import { useState } from "react";
import { ApiError, apiFetch } from "@/lib/api";
import { formatPesewas } from "@/lib/money";
import type { InitiatePaymentResponse } from "@/lib/types";

type Method = "momo" | "card";
type PayMode = "full" | "deposit";

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
  const [payMode, setPayMode] = useState<PayMode>("full");
  // Deposit input is in whole GHS for a simpler numeric input — converted
  // to pesewas on submit. Defaults to half the balance owed.
  const [depositGHS, setDepositGHS] = useState(
    ((amountOwedPesewas / 2 / 100) || 0).toFixed(2),
  );
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const depositPesewas = Math.round(parseFloat(depositGHS || "0") * 100);
  const depositValid =
    payMode === "full" ||
    (Number.isFinite(depositPesewas) &&
      depositPesewas > 0 &&
      depositPesewas <= amountOwedPesewas);
  const amountToPay = payMode === "deposit" ? depositPesewas : amountOwedPesewas;

  async function pay() {
    if (!depositValid) return;
    setLoading(true);
    setError(null);
    try {
      const res = await apiFetch<InitiatePaymentResponse>(
        `/api/v1/public/checkout/${reference}/pay`,
        {
          method: "POST",
          body: JSON.stringify({
            preferred_method: method,
            // Omitted (0) for "pay in full" — the server always computes
            // the exact current balance itself rather than trusting a
            // client-supplied full amount.
            amount_pesewas: payMode === "deposit" ? depositPesewas : 0,
          }),
        },
      );
      window.location.assign(res.authorization_url);
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

      <div className="mt-3 flex gap-2">
        <button
          type="button"
          onClick={() => setPayMode("full")}
          className={`flex-1 rounded-md border px-3 py-2 text-xs font-medium ${
            payMode === "full"
              ? "border-neutral-900 bg-neutral-900 text-white"
              : "border-neutral-300 text-neutral-700"
          }`}
        >
          Pay in full
        </button>
        <button
          type="button"
          onClick={() => setPayMode("deposit")}
          className={`flex-1 rounded-md border px-3 py-2 text-xs font-medium ${
            payMode === "deposit"
              ? "border-neutral-900 bg-neutral-900 text-white"
              : "border-neutral-300 text-neutral-700"
          }`}
        >
          Pay a deposit
        </button>
      </div>

      {payMode === "deposit" && (
        <div className="mt-3 space-y-1">
          <label className="text-xs text-neutral-500" htmlFor="deposit-amount">
            Deposit amount (GHS) — balance of{" "}
            {formatPesewas(amountOwedPesewas)} still due after
          </label>
          <input
            id="deposit-amount"
            type="number"
            step="0.01"
            min="0.01"
            max={(amountOwedPesewas / 100).toFixed(2)}
            value={depositGHS}
            onChange={(e) => setDepositGHS(e.target.value)}
            className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm"
          />
          {!depositValid && (
            <p className="text-xs text-red-600">
              Enter an amount between GH₵0.01 and{" "}
              {formatPesewas(amountOwedPesewas)}.
            </p>
          )}
        </div>
      )}

      {error && <p className="mt-3 text-sm text-red-600">{error}</p>}

      <button
        type="button"
        onClick={pay}
        disabled={loading || !depositValid}
        className="mt-4 w-full rounded-md bg-neutral-900 px-3 py-3 text-sm font-semibold text-white disabled:opacity-50"
      >
        {loading ? "Redirecting…" : `Pay ${formatPesewas(amountToPay)}`}
      </button>
    </div>
  );
}
