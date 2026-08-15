"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import type { FeeRule } from "@/lib/types";

const ALLOCATIONS = [
  { value: "customer_only", label: "Customer only" },
  { value: "merchant_only", label: "Merchant only" },
  { value: "split", label: "Split" },
];

export function GlobalFeeForm({ rule }: { rule: FeeRule | null }) {
  const router = useRouter();
  const [percent, setPercent] = useState(
    rule ? (rule.commission_bps / 100).toFixed(2) : "4.00",
  );
  const [allocation, setAllocation] = useState<string>(
    rule?.allocation_type ?? "customer_only",
  );
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError(null);
    setSaved(false);
    try {
      const commissionBps = Math.round(parseFloat(percent) * 100);
      const res = await fetch("/api/pricing/global", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          commission_bps: commissionBps,
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
        <label className="text-xs text-neutral-500" htmlFor="global-pct">
          Global commission rate (%)
        </label>
        <input
          id="global-pct"
          type="number"
          step="0.01"
          min="0"
          required
          value={percent}
          onChange={(e) => {
            setPercent(e.target.value);
            setSaved(false);
          }}
          className="rounded-md border border-neutral-300 px-3 py-2 text-sm"
        />
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
