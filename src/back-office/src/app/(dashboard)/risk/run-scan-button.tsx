"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export function RunScanButton() {
  const router = useRouter();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<string | null>(null);

  async function runScan() {
    setLoading(true);
    setError(null);
    setResult(null);
    try {
      const res = await fetch("/api/risk/scan", { method: "POST" });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error(data.error ?? "failed to run scan");
      }
      setResult(
        `Scan complete — ${data.duplicate_ghana_card_candidates} duplicate-card and ${data.velocity_spike_candidates} velocity candidates found (new flags only appear once, even across repeat scans).`,
      );
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "something went wrong");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="rounded-lg border border-neutral-200 p-4">
      <div className="flex items-center gap-3">
        <button
          type="button"
          disabled={loading}
          onClick={runScan}
          className="rounded-md bg-neutral-900 px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
        >
          {loading ? "Scanning…" : "Run scan"}
        </button>
        <p className="text-xs text-neutral-500">
          Checks for duplicate Ghana Card numbers across merchants and
          sudden invoice-volume/value spikes vs. each merchant&apos;s own
          trailing average. No scheduler yet — run manually.
        </p>
      </div>
      {result && <p className="mt-2 text-xs text-neutral-600">{result}</p>}
      {error && <p className="mt-2 text-xs text-red-600">{error}</p>}
    </div>
  );
}
