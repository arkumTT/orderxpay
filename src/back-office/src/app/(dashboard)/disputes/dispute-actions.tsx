"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { formatPesewas } from "@/lib/money";
import type { RefundablePayment } from "@/lib/types";

type Mode = "idle" | "deny" | "refund";

export function DisputeActions({
  disputeId,
  status,
}: {
  disputeId: string;
  status: "open" | "investigating";
}) {
  const router = useRouter();
  const [mode, setMode] = useState<Mode>("idle");
  const [reason, setReason] = useState("");
  const [payments, setPayments] = useState<RefundablePayment[] | null>(null);
  const [selectedPaymentId, setSelectedPaymentId] = useState("");
  const [amount, setAmount] = useState(""); // GHS, user-facing
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function reset() {
    setMode("idle");
    setReason("");
    setPayments(null);
    setSelectedPaymentId("");
    setAmount("");
    setError(null);
  }

  async function submit(body: Record<string, unknown>) {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`/api/disputes/${disputeId}/status`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error(data.error ?? "failed to update dispute");
      }
      reset();
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "something went wrong");
    } finally {
      setLoading(false);
    }
  }

  async function startRefund() {
    setMode("refund");
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`/api/disputes/${disputeId}`);
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error(data.error ?? "failed to load refundable payments");
      }
      const refundable: RefundablePayment[] = data.refundable_payments ?? [];
      setPayments(refundable);
      const first = refundable.find((p) => p.refundable_pesewas > 0);
      if (first) {
        setSelectedPaymentId(first.id);
        setAmount((first.refundable_pesewas / 100).toFixed(2));
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "something went wrong");
    } finally {
      setLoading(false);
    }
  }

  if (mode === "deny") {
    return (
      <div className="space-y-2">
        <label className="block text-xs text-neutral-500">
          Reason for denying
        </label>
        <textarea
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          rows={2}
          className="w-full rounded-md border border-neutral-300 px-2 py-1 text-xs"
          autoFocus
        />
        {error && <p className="text-xs text-red-600">{error}</p>}
        <div className="flex gap-2">
          <button
            type="button"
            disabled={loading || !reason.trim()}
            onClick={() =>
              submit({ status: "resolved_denied", resolution_notes: reason.trim() })
            }
            className="rounded-md bg-neutral-900 px-2 py-1 text-xs font-medium text-white disabled:opacity-50"
          >
            {loading ? "Saving…" : "Confirm denial"}
          </button>
          <button
            type="button"
            disabled={loading}
            onClick={reset}
            className="rounded-md border border-neutral-300 px-2 py-1 text-xs text-neutral-700"
          >
            Cancel
          </button>
        </div>
      </div>
    );
  }

  if (mode === "refund") {
    const selected = payments?.find((p) => p.id === selectedPaymentId);
    const amountPesewas = Math.round(parseFloat(amount || "0") * 100);
    const overLimit = selected ? amountPesewas > selected.refundable_pesewas : false;

    return (
      <div className="space-y-2">
        {payments === null ? (
          <p className="text-xs text-neutral-500">Loading payments…</p>
        ) : payments.length === 0 ? (
          <p className="text-xs text-neutral-500">
            No successful payments to refund on this invoice.
          </p>
        ) : (
          <>
            <label className="block text-xs text-neutral-500">Payment</label>
            <select
              value={selectedPaymentId}
              onChange={(e) => {
                setSelectedPaymentId(e.target.value);
                const p = payments.find((x) => x.id === e.target.value);
                if (p) setAmount((p.refundable_pesewas / 100).toFixed(2));
              }}
              className="w-full rounded-md border border-neutral-300 px-2 py-1 text-xs"
            >
              {payments.map((p) => (
                <option key={p.id} value={p.id} disabled={p.refundable_pesewas <= 0}>
                  {p.method} · {formatPesewas(p.amount_pesewas)} · refundable{" "}
                  {formatPesewas(p.refundable_pesewas)}
                </option>
              ))}
            </select>
            <label className="block text-xs text-neutral-500">
              Refund amount (GHS)
            </label>
            <input
              type="number"
              step="0.01"
              min="0"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              className="w-full rounded-md border border-neutral-300 px-2 py-1 text-xs"
            />
            {overLimit && (
              <p className="text-xs text-red-600">
                Exceeds the refundable balance on this payment.
              </p>
            )}
          </>
        )}
        {error && <p className="text-xs text-red-600">{error}</p>}
        <div className="flex gap-2">
          <button
            type="button"
            disabled={
              loading ||
              !selectedPaymentId ||
              amountPesewas <= 0 ||
              overLimit
            }
            onClick={() =>
              submit({
                status: "resolved_refunded",
                refund_payment_id: selectedPaymentId,
                refund_amount_pesewas: amountPesewas,
              })
            }
            className="rounded-md bg-neutral-900 px-2 py-1 text-xs font-medium text-white disabled:opacity-50"
          >
            {loading ? "Processing…" : "Confirm refund"}
          </button>
          <button
            type="button"
            disabled={loading}
            onClick={reset}
            className="rounded-md border border-neutral-300 px-2 py-1 text-xs text-neutral-700"
          >
            Cancel
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="flex flex-wrap items-center gap-2">
      {status === "open" && (
        <button
          type="button"
          onClick={() => submit({ status: "investigating" })}
          className="rounded-md border border-neutral-300 px-2 py-1 text-xs font-medium text-neutral-700 hover:bg-neutral-50"
        >
          Investigate
        </button>
      )}
      <button
        type="button"
        onClick={startRefund}
        className="rounded-md border border-green-300 bg-green-50 px-2 py-1 text-xs font-medium text-green-800 hover:bg-green-100"
      >
        Refund
      </button>
      <button
        type="button"
        onClick={() => setMode("deny")}
        className="rounded-md border border-red-300 bg-red-50 px-2 py-1 text-xs font-medium text-red-800 hover:bg-red-100"
      >
        Deny
      </button>
    </div>
  );
}
