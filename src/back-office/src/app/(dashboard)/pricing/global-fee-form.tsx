"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import type { FeeRule } from "@/lib/types";

const ALLOCATIONS = [
  { value: "customer_only", label: "Customer only" },
  { value: "merchant_only", label: "Merchant only" },
  { value: "split", label: "Split" },
];

// Section 4.8 (revised): the blended platform rate is composed of three
// separately-tunable components — collection fee, payout fee, margin — so a
// PSP pricing change doesn't require hand-deriving a new blended figure.
// commission_bps itself is derived server-side and shown read-only here.
export function GlobalFeeForm({ rule }: { rule: FeeRule | null }) {
  const router = useRouter();
  const [collectionPct, setCollectionPct] = useState(
    rule ? (rule.collection_fee_bps / 100).toFixed(2) : "2.00",
  );
  const [payoutPct, setPayoutPct] = useState(
    rule ? (rule.payout_fee_bps / 100).toFixed(2) : "1.00",
  );
  const [marginPct, setMarginPct] = useState(
    rule ? (rule.margin_bps / 100).toFixed(2) : "1.00",
  );
  const [allocation, setAllocation] = useState<string>(
    rule?.allocation_type ?? "customer_only",
  );
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  const blendedPct = (
    (parseFloat(collectionPct) || 0) +
    (parseFloat(payoutPct) || 0) +
    (parseFloat(marginPct) || 0)
  ).toFixed(2);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError(null);
    setSaved(false);
    try {
      const res = await fetch("/api/pricing/global", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          collection_fee_bps: Math.round(parseFloat(collectionPct) * 100),
          payout_fee_bps: Math.round(parseFloat(payoutPct) * 100),
          margin_bps: Math.round(parseFloat(marginPct) * 100),
          allocation_type: allocation,
        }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error(data.error ?? "failed to update global rate");
      }
      setSaved(true);
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
        <label className="text-xs text-neutral-500" htmlFor="global-collection">
          Collection fee (PSP) %
        </label>
        <input
          id="global-collection"
          type="number"
          step="0.01"
          min="0"
          required
          value={collectionPct}
          onChange={(e) => {
            setCollectionPct(e.target.value);
            setSaved(false);
          }}
          className="w-28 rounded-md border border-neutral-300 px-3 py-2 text-sm"
        />
      </div>
      <div className="space-y-1">
        <label className="text-xs text-neutral-500" htmlFor="global-payout">
          Payout fee (PSP) %
        </label>
        <input
          id="global-payout"
          type="number"
          step="0.01"
          min="0"
          required
          value={payoutPct}
          onChange={(e) => {
            setPayoutPct(e.target.value);
            setSaved(false);
          }}
          className="w-28 rounded-md border border-neutral-300 px-3 py-2 text-sm"
        />
      </div>
      <div className="space-y-1">
        <label className="text-xs text-neutral-500" htmlFor="global-margin">
          Margin %
        </label>
        <input
          id="global-margin"
          type="number"
          step="0.01"
          min="0"
          required
          value={marginPct}
          onChange={(e) => {
            setMarginPct(e.target.value);
            setSaved(false);
          }}
          className="w-28 rounded-md border border-neutral-300 px-3 py-2 text-sm"
        />
      </div>
      <div className="space-y-1">
        <span className="text-xs text-neutral-500">Blended rate</span>
        <p className="rounded-md border border-transparent px-3 py-2 text-sm font-semibold text-neutral-900">
          {blendedPct}%
        </p>
      </div>
      <div className="space-y-1">
        <label className="text-xs text-neutral-500" htmlFor="global-alloc">
          Default service-charge allocation
        </label>
        <select
          id="global-alloc"
          value={allocation}
          onChange={(e) => {
            setAllocation(e.target.value);
            setSaved(false);
          }}
          className="rounded-md border border-neutral-300 px-3 py-2 text-sm"
        >
          {ALLOCATIONS.map((a) => (
            <option key={a.value} value={a.value}>
              {a.label}
            </option>
          ))}
        </select>
      </div>
      <button
        type="submit"
        disabled={loading}
        className="rounded-md bg-neutral-900 px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
      >
        {loading ? "Saving…" : "Save global rate"}
      </button>
      {saved && !error && (
        <span className="text-xs text-green-700">Saved</span>
      )}
      {error && <p className="w-full text-sm text-red-600">{error}</p>}
    </form>
  );
}
