"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Settlement } from "@/lib/types";

// Mirrors settlementStatusTransitions in the API (payments.go) — kept in
// sync by hand since it's a small, stable enum, not worth a shared package.
const NEXT_STATUSES: Record<Settlement["status"], Settlement["status"][]> = {
  pending: ["processing", "paid", "failed"],
  processing: ["paid", "failed"],
  paid: [],
  failed: [],
};

const LABEL: Record<Settlement["status"], string> = {
  pending: "Mark pending",
  processing: "Mark processing",
  paid: "Mark paid",
  failed: "Mark failed",
};

export function SettlementStatusActions({
  settlementId,
  status,
}: {
  settlementId: string;
  status: Settlement["status"];
}) {
  const router = useRouter();
  const [loading, setLoading] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const nextStatuses = NEXT_STATUSES[status];
  if (nextStatuses.length === 0) return null;

  async function updateStatus(next: string) {
    setLoading(next);
    setError(null);
    try {
      const res = await fetch(`/api/settlements/${settlementId}/status`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ status: next }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error(data.error ?? "failed to update settlement");
      }
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "something went wrong");
    } finally {
      setLoading(null);
    }
  }

  return (
    <div className="flex flex-wrap items-center gap-2">
      {nextStatuses.map((next) => (
        <button
          key={next}
          type="button"
          disabled={loading !== null}
          onClick={() => updateStatus(next)}
          className="rounded-md border border-neutral-300 px-2 py-1 text-xs font-medium text-neutral-700 hover:bg-neutral-50 disabled:opacity-50"
        >
          {loading === next ? "…" : LABEL[next]}
        </button>
      ))}
      {error && <span className="text-xs text-red-600">{error}</span>}
    </div>
  );
}
