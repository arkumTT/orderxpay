"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import type { FeeRule } from "@/lib/types";

const ALLOCATIONS = [
  { value: "customer_only", label: "Customer only" },
  { value: "merchant_only", label: "Merchant only" },
  { value: "split", label: "Split" },
];

// Section 4.8, revised again in migration 000028. The blended rate is the
// PSP's collection fee passed through plus OrderxPay's own margin, so a PSP
// price change doesn't require hand-deriving a new blended figure.
// commission_bps is derived server-side and shown read-only here.
//
// The payout side is not a rate: the PSP charges a flat amount per transfer,
// so it is set here in cedis and waived above a threshold. The margin floor
// and cap clamp OrderxPay's take per invoice — never the pass-through — so
// small invoices stay worth carrying and large ones stay worth paying.
export function GlobalFeeForm({ rule }: { rule: FeeRule | null }) {
  const router = useRouter();
  const [collectionPct, setCollectionPct] = useState(
    rule ? (rule.collection_fee_bps / 100).toFixed(2) : "1.95",
  );
  const [marginPct, setMarginPct] = useState(
    rule ? (rule.margin_bps / 100).toFixed(2) : "0.55",
  );
  const [marginFloorGhs, setMarginFloorGhs] = useState(
    rule ? (rule.margin_floor_pesewas / 100).toFixed(2) : "0.20",
  );
  const [marginCapGhs, setMarginCapGhs] = useState(
    rule ? (rule.margin_cap_pesewas / 100).toFixed(2) : "25.00",
  );
  const [momoFeeGhs, setMomoFeeGhs] = useState(
    rule ? (rule.withdrawal_fee_momo_pesewas / 100).toFixed(2) : "1.00",
  );
  const [bankFeeGhs, setBankFeeGhs] = useState(
    rule ? (rule.withdrawal_fee_bank_pesewas / 100).toFixed(2) : "8.00",
  );
  const [waiverGhs, setWaiverGhs] = useState(
    rule ? (rule.withdrawal_fee_waiver_pesewas / 100).toFixed(2) : "500.00",
  );
  const [allocation, setAllocation] = useState<string>(
    rule?.allocation_type ?? "customer_only",
  );
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  const blendedPct = (
    (parseFloat(collectionPct) || 0) + (parseFloat(marginPct) || 0)
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
          margin_bps: Math.round(parseFloat(marginPct) * 100),
          allocation_type: allocation,
          margin_floor_pesewas: Math.round(parseFloat(marginFloorGhs) * 100),
          margin_cap_pesewas: Math.round(parseFloat(marginCapGhs) * 100),
          withdrawal_fee_momo_pesewas: Math.round(parseFloat(momoFeeGhs) * 100),
          withdrawal_fee_bank_pesewas: Math.round(parseFloat(bankFeeGhs) * 100),
          withdrawal_fee_waiver_pesewas: Math.round(parseFloat(waiverGhs) * 100),
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
        <label className="text-xs text-neutral-500" htmlFor="global-floor">
          Margin floor ₵
          </label>
        <input
          id="global-floor"
          type="number"
          step="0.01"
          min="0"
          required
          value={marginFloorGhs}
          onChange={(e) => setMarginFloorGhs(e.target.value)}
          className="w-28 rounded-md border border-neutral-300 px-3 py-2 text-sm"
          />
      </div>
      <div className="space-y-1">
        <label className="text-xs text-neutral-500" htmlFor="global-cap">
          Margin cap ₵
          </label>
        <input
          id="global-cap"
          type="number"
          step="0.01"
          min="0"
          required
          value={marginCapGhs}
          onChange={(e) => setMarginCapGhs(e.target.value)}
          className="w-28 rounded-md border border-neutral-300 px-3 py-2 text-sm"
          />
      </div>
      <div className="space-y-1">
        <label className="text-xs text-neutral-500" htmlFor="global-momo">
          MoMo payout ₵
          </label>
        <input
          id="global-momo"
          type="number"
          step="0.01"
          min="0"
          required
          value={momoFeeGhs}
          onChange={(e) => setMomoFeeGhs(e.target.value)}
          className="w-28 rounded-md border border-neutral-300 px-3 py-2 text-sm"
          />
      </div>
      <div className="space-y-1">
        <label className="text-xs text-neutral-500" htmlFor="global-bank">
          Bank payout ₵
          </label>
        <input
          id="global-bank"
          type="number"
          step="0.01"
          min="0"
          required
          value={bankFeeGhs}
          onChange={(e) => setBankFeeGhs(e.target.value)}
          className="w-28 rounded-md border border-neutral-300 px-3 py-2 text-sm"
          />
      </div>
      <div className="space-y-1">
        <label className="text-xs text-neutral-500" htmlFor="global-waiver">
          Payout free above ₵
          </label>
        <input
          id="global-waiver"
          type="number"
          step="0.01"
          min="0"
          required
          value={waiverGhs}
          onChange={(e) => setWaiverGhs(e.target.value)}
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
