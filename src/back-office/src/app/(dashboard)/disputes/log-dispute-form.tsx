"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import type { DisputeReason } from "@/lib/types";

const REASONS: { value: DisputeReason; label: string }[] = [
  { value: "not_received", label: "Goods not received" },
  { value: "wrong_item", label: "Wrong item" },
  { value: "damaged", label: "Damaged" },
  { value: "duplicate_charge", label: "Duplicate charge" },
  { value: "not_as_described", label: "Not as described" },
  { value: "other", label: "Other" },
];

export function LogDisputeForm() {
  const router = useRouter();
  const [invoiceReference, setInvoiceReference] = useState("");
  const [reasonCategory, setReasonCategory] = useState<DisputeReason>(
    "not_received",
  );
  const [description, setDescription] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError(null);
    try {
      const res = await fetch("/api/disputes", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          invoice_reference: invoiceReference.trim(),
          reason_category: reasonCategory,
          description: description.trim(),
        }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error(data.error ?? "failed to log dispute");
      }
      setInvoiceReference("");
      setDescription("");
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "something went wrong");
    } finally {
      setLoading(false);
    }
  }

  return (
    <form
      onSubmit={handleSubmit}
      className="flex flex-wrap items-end gap-3 rounded-lg border border-neutral-200 p-4"
    >
      <div className="space-y-1">
        <label className="text-xs text-neutral-500" htmlFor="invoice-ref">
          Invoice reference
        </label>
        <input
          id="invoice-ref"
          required
          value={invoiceReference}
          onChange={(e) => setInvoiceReference(e.target.value)}
          placeholder="INV-XXXXXXXXXX"
          className="rounded-md border border-neutral-300 px-3 py-2 text-sm uppercase placeholder:normal-case"
        />
      </div>
      <div className="space-y-1">
        <label className="text-xs text-neutral-500" htmlFor="reason">
          Reason
        </label>
        <select
          id="reason"
          value={reasonCategory}
          onChange={(e) => setReasonCategory(e.target.value as DisputeReason)}
          className="rounded-md border border-neutral-300 px-3 py-2 text-sm"
        >
          {REASONS.map((r) => (
            <option key={r.value} value={r.value}>
              {r.label}
            </option>
          ))}
        </select>
      </div>
      <div className="min-w-[220px] flex-1 space-y-1">
        <label className="text-xs text-neutral-500" htmlFor="description">
          Description (optional)
        </label>
        <input
          id="description"
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          placeholder="What the customer reported"
          className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm"
        />
      </div>
      <button
        type="submit"
        disabled={loading || !invoiceReference.trim()}
        className="rounded-md bg-neutral-900 px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
      >
        {loading ? "Logging…" : "Log dispute"}
      </button>
      {error && <p className="w-full text-sm text-red-600">{error}</p>}
    </form>
  );
}
