"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export function MerchantKYCTierActions({
  merchantId,
  kycTier,
}: {
  merchantId: string;
  kycTier: number;
}) {
  const router = useRouter();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function setTier(tier: 0 | 1) {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`/api/merchants/${merchantId}/kyc-tier`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ kyc_tier: tier }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error ?? "failed to update KYC tier");
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "something went wrong");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="flex flex-wrap items-center gap-2">
      {[0, 1].map((tier) => (
        <button
          key={tier}
          type="button"
          disabled={loading || kycTier === tier}
          onClick={() => setTier(tier as 0 | 1)}
          className={`rounded-md border px-3 py-2 text-sm font-medium disabled:opacity-50 ${
            kycTier === tier
              ? "border-neutral-900 bg-neutral-900 text-white"
              : "border-neutral-300 text-neutral-700 hover:bg-neutral-50"
          }`}
        >
          Tier {tier}
        </button>
      ))}
      <p className="text-xs text-neutral-400">
        Direct override — bypasses the KYC submission review queue.
      </p>
      {error && <p className="w-full text-xs text-red-600">{error}</p>}
    </div>
  );
}
