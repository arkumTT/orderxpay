"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import type { KYCTierLimit } from "@/lib/types";

const TIER_NAMES: Record<number, { name: string; evidence: string }> = {
  0: { name: "Tier 0", evidence: "Unverified — signed up, nothing submitted" },
  1: { name: "Tier 1", evidence: "Informal — Ghana Card number + liveness check" },
  2: {
    name: "Tier 2",
    evidence: "Registered — Tier 1 evidence + TIN, reg number, certificate",
  },
};

// Pesewas ⇄ cedis at the edge only. An empty box is null ("no cap"), which
// is a different thing from 0 and has to stay different all the way to the
// database — 0 would block all trading at that tier.
function toGhs(pesewas: number | null): string {
  return pesewas === null ? "" : (pesewas / 100).toFixed(2);
}

function toPesewas(ghs: string): number | null {
  const trimmed = ghs.trim();
  if (trimmed === "") return null;
  const parsed = Number.parseFloat(trimmed);
  if (!Number.isFinite(parsed)) return null;
  return Math.round(parsed * 100);
}

function TierRow({ limit }: { limit: KYCTierLimit }) {
  const router = useRouter();
  const [perTx, setPerTx] = useState(toGhs(limit.per_transaction_pesewas));
  const [daily, setDaily] = useState(toGhs(limit.daily_pesewas));
  const [cumulative, setCumulative] = useState(toGhs(limit.cumulative_pesewas));
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  const tier = TIER_NAMES[limit.tier];
  const uncapped = !perTx.trim() && !daily.trim() && !cumulative.trim();

  async function handleSave() {
    setLoading(true);
    setError(null);
    setSaved(false);
    try {
      const res = await fetch(`/api/kyc-tier-limits/${limit.tier}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          per_transaction_pesewas: toPesewas(perTx),
          daily_pesewas: toPesewas(daily),
          cumulative_pesewas: toPesewas(cumulative),
        }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error ?? "failed to save limits");
      setSaved(true);
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "failed to save limits");
    } finally {
      setLoading(false);
    }
  }

  return (
    <tr className="align-top">
      <td className="px-4 py-3">
        <div className="font-medium text-neutral-900">{tier.name}</div>
        <div className="max-w-xs text-xs text-neutral-500">{tier.evidence}</div>
        {uncapped && (
          <div className="mt-1 text-xs font-medium text-amber-700">
            No limits set — this tier is uncapped
          </div>
        )}
      </td>
      {(
        [
          [perTx, setPerTx, "per-payment"],
          [daily, setDaily, "daily"],
          [cumulative, setCumulative, "lifetime"],
        ] as const
      ).map(([value, setValue, label]) => (
        <td key={label} className="px-4 py-3">
          <div className="flex items-center gap-1">
            <span className="text-xs text-neutral-400">GH₵</span>
            <input
              type="number"
              step="0.01"
              min="0.01"
              value={value}
              onChange={(e) => setValue(e.target.value)}
              placeholder="No cap"
              aria-label={`Tier ${limit.tier} ${label} limit in cedis`}
              className="w-28 rounded border border-neutral-300 px-2 py-1 text-sm"
            />
          </div>
        </td>
      ))}
      <td className="px-4 py-3">
        <button
          type="button"
          onClick={handleSave}
          disabled={loading}
          className="rounded bg-neutral-900 px-3 py-1 text-sm font-medium text-white disabled:opacity-50"
        >
          {loading ? "Saving…" : "Save"}
        </button>
        {saved && <div className="mt-1 text-xs text-green-700">Saved</div>}
        {error && <div className="mt-1 max-w-xs text-xs text-red-600">{error}</div>}
      </td>
    </tr>
  );
}

export function TierLimits({ limits }: { limits: KYCTierLimit[] }) {
  const anySet = limits.some(
    (l) =>
      l.per_transaction_pesewas !== null ||
      l.daily_pesewas !== null ||
      l.cumulative_pesewas !== null,
  );

  return (
    <section className="rounded-lg border border-neutral-200">
      <div className="border-b border-neutral-200 bg-neutral-50 px-4 py-3">
        <h2 className="text-sm font-semibold text-neutral-700">
          Tier limits
        </h2>
        <p className="mt-1 text-xs text-neutral-500">
          What each tier is allowed to collect. Checked when a merchant
          raises an invoice and again when a customer starts a payment.
          Leave a box empty for no cap.
        </p>
      </div>

      {!anySet && (
        <div className="border-b border-amber-200 bg-amber-50 px-4 py-3 text-xs text-amber-900">
          <strong>No limits are set, so no tier is capped.</strong> These
          thresholds are governed by Bank of Ghana guidance and were
          deliberately shipped empty rather than pre-filled with figures
          nobody had verified. Confirm the current official guidance before
          entering values here — enforcement starts the moment you do.
        </div>
      )}

      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="bg-white text-left text-xs uppercase tracking-wide text-neutral-500">
            <tr>
              <th className="px-4 py-2">Tier</th>
              <th className="px-4 py-2">Per payment</th>
              <th className="px-4 py-2">Per day</th>
              <th className="px-4 py-2">Lifetime</th>
              <th className="px-4 py-2">&nbsp;</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-neutral-100">
            {limits.map((l) => (
              <TierRow key={l.tier} limit={l} />
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}
