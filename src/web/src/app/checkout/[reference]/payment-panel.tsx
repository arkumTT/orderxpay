"use client";

import { useState } from "react";
import { ApiError, apiFetch } from "@/lib/api";
import { formatPesewas } from "@/lib/money";
import type { InitiatePaymentResponse } from "@/lib/types";

type Method = "momo" | "card" | "ussd";
type PayMode = "full" | "deposit";

const METHODS: { value: Method; label: string }[] = [
  { value: "momo", label: "Mobile Money" },
  { value: "card", label: "Card" },
  { value: "ussd", label: "Dial USSD" },
];

// Client component: the Pay button needs to redirect the browser to
// Paystack's hosted checkout page (Section 5.1, 9.1), which a Server
// Component can't do. The method chips below are a preference hint only
// (see PreferredMethod in api/internal/http/handlers/payments.go) — the
// customer still picks their actual channel on Paystack's own page, so
// this never collects a Mobile Money number or card details itself.
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
    <div className="flex flex-col gap-4">
      <div className="flex gap-2">
        {METHODS.map((m) => (
          <button
            key={m.value}
            type="button"
            onClick={() => setMethod(m.value)}
            className={`h-9 flex-1 whitespace-nowrap rounded-full px-2 text-[11px] font-bold transition-colors sm:text-xs ${
              method === m.value
                ? "bg-oxp-black text-white"
                : "border border-oxp-border bg-white text-oxp-black"
            }`}
          >
            {m.label}
          </button>
        ))}
      </div>

      <div className="rounded-2xl border border-oxp-border bg-white p-4">
        <div className="flex gap-2">
          <button
            type="button"
            onClick={() => setPayMode("full")}
            className={`h-9 flex-1 rounded-lg text-xs font-bold transition-colors ${
              payMode === "full"
                ? "bg-oxp-black text-white"
                : "border border-oxp-border bg-white text-oxp-black"
            }`}
          >
            Pay in full
          </button>
          <button
            type="button"
            onClick={() => setPayMode("deposit")}
            className={`h-9 flex-1 rounded-lg text-xs font-bold transition-colors ${
              payMode === "deposit"
                ? "bg-oxp-black text-white"
                : "border border-oxp-border bg-white text-oxp-black"
            }`}
          >
            Pay a deposit
          </button>
        </div>

        {payMode === "deposit" && (
          <div className="mt-3 flex flex-col gap-1.5">
            <label
              className="text-xs font-semibold text-oxp-black"
              htmlFor="deposit-amount"
            >
              Deposit amount (GHS)
            </label>
            <input
              id="deposit-amount"
              type="number"
              step="0.01"
              min="0.01"
              max={(amountOwedPesewas / 100).toFixed(2)}
              value={depositGHS}
              onChange={(e) => setDepositGHS(e.target.value)}
              className="rounded-xl border border-oxp-border bg-oxp-fill px-3.5 py-3 text-sm text-oxp-black"
            />
            <p className="text-xs text-oxp-muted">
              Balance of {formatPesewas(amountOwedPesewas)} still due after.
            </p>
            {!depositValid && (
              <p className="text-xs font-medium text-oxp-red">
                Enter an amount between GH₵0.01 and{" "}
                {formatPesewas(amountOwedPesewas)}.
              </p>
            )}
          </div>
        )}
      </div>

      {error && <p className="text-sm text-oxp-red">{error}</p>}

      <button
        type="button"
        onClick={pay}
        disabled={loading || !depositValid}
        className="flex h-[52px] w-full items-center justify-center rounded-xl bg-oxp-green text-base font-bold text-white transition-opacity disabled:opacity-50"
      >
        {loading ? "Redirecting…" : `Pay ${formatPesewas(amountToPay)}`}
      </button>
    </div>
  );
}
