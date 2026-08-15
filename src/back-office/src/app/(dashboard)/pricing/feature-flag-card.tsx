"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import type { FeatureFlag, Merchant } from "@/lib/types";

export function FeatureFlagCard({
  flag,
  merchants,
}: {
  flag: FeatureFlag;
  merchants: Merchant[];
}) {
  const router = useRouter();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [merchantToAdd, setMerchantToAdd] = useState("");

  const optedInIds = new Set(flag.merchants.map((m) => m.merchant_id));
  const availableMerchants = merchants.filter((m) => !optedInIds.has(m.id));

  async function toggleGlobal() {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`/api/feature-flags/${flag.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ enabled_globally: !flag.enabled_globally }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error ?? "failed to update flag");
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "something went wrong");
    } finally {
      setLoading(false);
    }
  }

  async function addMerchant() {
    if (!merchantToAdd) return;
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`/api/feature-flags/${flag.id}/merchants`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ merchant_id: merchantToAdd }),
      });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data.error ?? "failed to add merchant");
      }
      setMerchantToAdd("");
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "something went wrong");
    } finally {
      setLoading(false);
    }
  }

  async function removeMerchant(merchantId: string) {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(
        `/api/feature-flags/${flag.id}/merchants/${merchantId}`,
        { method: "DELETE" },
      );
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data.error ?? "failed to remove merchant");
      }
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "something went wrong");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="rounded-lg border border-neutral-200 p-4">
      <div className="flex items-start justify-between gap-3">
        <div>
          <div className="font-medium text-neutral-900">{flag.name}</div>
          <div className="text-xs text-neutral-400">{flag.key}</div>
          {flag.description && (
            <div className="mt-1 text-xs text-neutral-500">
              {flag.description}
            </div>
          )}
        </div>
        <button
          type="button"
          disabled={loading}
          onClick={toggleGlobal}
          className={`shrink-0 rounded-full px-3 py-1 text-xs font-medium disabled:opacity-50 ${
            flag.enabled_globally
              ? "bg-green-100 text-green-800"
              : "bg-neutral-100 text-neutral-600"
          }`}
        >
          {loading ? "…" : flag.enabled_globally ? "Enabled globally" : "Disabled globally"}
        </button>
      </div>

      {flag.enabled_globally ? (
        <p className="mt-3 text-xs text-neutral-400">
          Everyone has this — per-merchant opt-in is moot until it&apos;s
          turned back off.
        </p>
      ) : (
        <div className="mt-3">
          <div className="flex flex-wrap gap-1">
            {flag.merchants.length === 0 && (
              <span className="text-xs text-neutral-400">
                No merchants opted in yet
              </span>
            )}
            {flag.merchants.map((m) => (
              <span
                key={m.merchant_id}
                className="flex items-center gap-1 rounded-full bg-neutral-100 px-2 py-0.5 text-xs font-medium text-neutral-700"
              >
                {m.business_name}
                <button
                  type="button"
                  disabled={loading}
                  onClick={() => removeMerchant(m.merchant_id)}
                  className="text-neutral-400 hover:text-red-600 disabled:opacity-50"
                  aria-label={`Remove ${m.business_name}`}
                >
                  ×
                </button>
              </span>
            ))}
          </div>
          {availableMerchants.length > 0 && (
            <div className="mt-2 flex gap-1">
              <select
                value={merchantToAdd}
                onChange={(e) => setMerchantToAdd(e.target.value)}
                className="rounded-md border border-neutral-300 px-1 py-0.5 text-xs"
              >
                <option value="">+ Add merchant…</option>
                {availableMerchants.map((m) => (
                  <option key={m.id} value={m.id}>
                    {m.business_name}
                  </option>
                ))}
              </select>
              <button
                type="button"
                disabled={loading || !merchantToAdd}
                onClick={addMerchant}
                className="rounded-md border border-neutral-300 px-2 py-0.5 text-xs text-neutral-700 hover:bg-neutral-50 disabled:opacity-50"
              >
                Add
              </button>
            </div>
          )}
        </div>
      )}
      {error && <p className="mt-2 text-xs text-red-600">{error}</p>}
    </div>
  );
}
