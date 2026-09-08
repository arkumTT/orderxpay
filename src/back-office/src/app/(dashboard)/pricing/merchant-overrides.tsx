"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import type { FeeRuleOverride, Merchant } from "@/lib/types";

const ALLOCATIONS = [
  { value: "customer_only", label: "Customer only" },
  { value: "merchant_only", label: "Merchant only" },
  { value: "split", label: "Split" },
];

function formatDate(d: string) {
  return new Date(d).toLocaleDateString("en-GH", {
    day: "2-digit",
    month: "short",
    year: "numeric",
  });
}

export function MerchantOverrides({
  overrides,
  merchants,
}: {
  overrides: FeeRuleOverride[];
  merchants: Merchant[];
}) {
  const router = useRouter();
  const [merchantId, setMerchantId] = useState("");
  const [collectionPct, setCollectionPct] = useState("1.95");
  const [marginPct, setMarginPct] = useState("0.55");
  const [marginFloorGhs, setMarginFloorGhs] = useState("0.20");
  const [marginCapGhs, setMarginCapGhs] = useState("25.00");
  const [momoFeeGhs, setMomoFeeGhs] = useState("1.00");
  const [bankFeeGhs, setBankFeeGhs] = useState("8.00");
  const [waiverGhs, setWaiverGhs] = useState("500.00");
  const [allocation, setAllocation] = useState("customer_only");
  const [loading, setLoading] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const blendedPct = (
    (parseFloat(collectionPct) || 0) + (parseFloat(marginPct) || 0)
  ).toFixed(2);

  async function addOverride(e: React.FormEvent) {
    e.preventDefault();
    if (!merchantId) return;
    setLoading("add");
    setError(null);
    try {
      const res = await fetch(`/api/pricing/merchant-overrides/${merchantId}`, {
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
      if (!res.ok) throw new Error(data.error ?? "failed to set override");
      setMerchantId("");
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "something went wrong");
    } finally {
      setLoading(null);
    }
  }

  async function removeOverride(id: string) {
    setLoading(id);
    setError(null);
    try {
      const res = await fetch(`/api/pricing/merchant-overrides/${id}`, {
        method: "DELETE",
      });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data.error ?? "failed to remove override");
      }
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "something went wrong");
    } finally {
      setLoading(null);
    }
  }

  return (
    <div className="space-y-3">
      <form
        onSubmit={addOverride}
        className="flex flex-wrap items-end gap-3 rounded-lg border border-neutral-200 p-4"
      >
        <div className="space-y-1">
          <label className="text-xs text-neutral-500" htmlFor="override-merchant">
            Merchant
          </label>
          <select
            id="override-merchant"
            required
            value={merchantId}
            onChange={(e) => setMerchantId(e.target.value)}
            className="rounded-md border border-neutral-300 px-3 py-2 text-sm"
          >
            <option value="">Select…</option>
            {merchants.map((m) => (
              <option key={m.id} value={m.id}>
                {m.business_name}
              </option>
            ))}
          </select>
        </div>
        <div className="space-y-1">
          <label className="text-xs text-neutral-500" htmlFor="override-collection">
            Collection fee %
          </label>
          <input
            id="override-collection"
            type="number"
            step="0.01"
            min="0"
            required
            value={collectionPct}
            onChange={(e) => setCollectionPct(e.target.value)}
            className="w-24 rounded-md border border-neutral-300 px-3 py-2 text-sm"
          />
        </div>
        <div className="space-y-1">
          <label className="text-xs text-neutral-500" htmlFor="override-floor">
            Margin floor ₵
          </label>
          <input
            id="override-floor"
            type="number"
            step="0.01"
            min="0"
            required
            value={marginFloorGhs}
            onChange={(e) => setMarginFloorGhs(e.target.value)}
            className="w-24 rounded-md border border-neutral-300 px-3 py-2 text-sm"
          />
        </div>
        <div className="space-y-1">
          <label className="text-xs text-neutral-500" htmlFor="override-cap">
            Margin cap ₵
          </label>
          <input
            id="override-cap"
            type="number"
            step="0.01"
            min="0"
            required
            value={marginCapGhs}
            onChange={(e) => setMarginCapGhs(e.target.value)}
            className="w-24 rounded-md border border-neutral-300 px-3 py-2 text-sm"
          />
        </div>
        <div className="space-y-1">
          <label className="text-xs text-neutral-500" htmlFor="override-momo">
            MoMo payout ₵
          </label>
          <input
            id="override-momo"
            type="number"
            step="0.01"
            min="0"
            required
            value={momoFeeGhs}
            onChange={(e) => setMomoFeeGhs(e.target.value)}
            className="w-24 rounded-md border border-neutral-300 px-3 py-2 text-sm"
          />
        </div>
        <div className="space-y-1">
          <label className="text-xs text-neutral-500" htmlFor="override-bank">
            Bank payout ₵
          </label>
          <input
            id="override-bank"
            type="number"
            step="0.01"
            min="0"
            required
            value={bankFeeGhs}
            onChange={(e) => setBankFeeGhs(e.target.value)}
            className="w-24 rounded-md border border-neutral-300 px-3 py-2 text-sm"
          />
        </div>
        <div className="space-y-1">
          <label className="text-xs text-neutral-500" htmlFor="override-waiver">
            Payout free above ₵
          </label>
          <input
            id="override-waiver"
            type="number"
            step="0.01"
            min="0"
            required
            value={waiverGhs}
            onChange={(e) => setWaiverGhs(e.target.value)}
            className="w-24 rounded-md border border-neutral-300 px-3 py-2 text-sm"
          />
        </div>
        <div className="space-y-1">
          <label className="text-xs text-neutral-500" htmlFor="override-margin">
            Margin %
          </label>
          <input
            id="override-margin"
            type="number"
            step="0.01"
            min="0"
            required
            value={marginPct}
            onChange={(e) => setMarginPct(e.target.value)}
            className="w-24 rounded-md border border-neutral-300 px-3 py-2 text-sm"
          />
        </div>
        <div className="space-y-1">
          <span className="text-xs text-neutral-500">Blended</span>
          <p className="px-3 py-2 text-sm font-semibold text-neutral-900">
            {blendedPct}%
          </p>
        </div>
        <div className="space-y-1">
          <label className="text-xs text-neutral-500" htmlFor="override-alloc">
            Allocation
          </label>
          <select
            id="override-alloc"
            value={allocation}
            onChange={(e) => setAllocation(e.target.value)}
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
          disabled={loading === "add" || !merchantId}
          className="rounded-md bg-neutral-900 px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
        >
          {loading === "add" ? "Saving…" : "Set override"}
        </button>
        {error && <p className="w-full text-sm text-red-600">{error}</p>}
      </form>

      {overrides.length === 0 ? (
        <p className="text-sm text-neutral-500">
          No merchant-specific overrides — everyone is on the global rate.
        </p>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-neutral-200">
          <table className="w-full text-sm">
            <thead className="bg-neutral-50 text-left text-xs uppercase tracking-wide text-neutral-500">
              <tr>
                <th className="px-4 py-2">Merchant</th>
                <th className="px-4 py-2">Rate</th>
                <th className="px-4 py-2">Allocation</th>
                <th className="px-4 py-2">Updated</th>
                <th className="px-4 py-2">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-neutral-100">
              {overrides.map((o) => (
                <tr key={o.id} className="hover:bg-neutral-50">
                  <td className="px-4 py-2 font-medium text-neutral-900">
                    {o.merchant_business_name}
                  </td>
                  <td className="px-4 py-2 text-neutral-600">
                    {(o.commission_bps / 100).toFixed(2)}%
                  </td>
                  <td className="px-4 py-2 text-neutral-600">
                    {o.allocation_type.replace("_", " ")}
                  </td>
                  <td className="px-4 py-2 text-neutral-500">
                    {formatDate(o.updated_at)}
                  </td>
                  <td className="px-4 py-2">
                    <button
                      type="button"
                      disabled={loading === o.merchant_id}
                      onClick={() => removeOverride(o.merchant_id!)}
                      className="rounded-md border border-neutral-300 px-2 py-1 text-xs text-neutral-700 hover:bg-neutral-50 disabled:opacity-50"
                    >
                      {loading === o.merchant_id ? "…" : "Revert to global"}
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
