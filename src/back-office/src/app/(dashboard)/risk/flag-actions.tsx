"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

type Mode = "idle" | "escalate";

export function FlagActions({ flagId }: { flagId: string }) {
  const router = useRouter();
  const [mode, setMode] = useState<Mode>("idle");
  const [notes, setNotes] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(status: string, resolutionNotes: string) {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`/api/risk/flags/${flagId}/status`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ status, resolution_notes: resolutionNotes }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error(data.error ?? "failed to update flag");
      }
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "something went wrong");
      setLoading(false);
    }
  }

  if (mode === "escalate") {
    return (
      <div className="space-y-2">
        <label className="block text-xs text-neutral-500">
          Escalation notes
        </label>
        <textarea
          value={notes}
          onChange={(e) => setNotes(e.target.value)}
          rows={2}
          className="w-full rounded-md border border-neutral-300 px-2 py-1 text-xs"
          autoFocus
        />
        {error && <p className="text-xs text-red-600">{error}</p>}
        <div className="flex gap-2">
          <button
            type="button"
            disabled={loading || !notes.trim()}
            onClick={() => submit("escalated", notes.trim())}
            className="rounded-md bg-neutral-900 px-2 py-1 text-xs font-medium text-white disabled:opacity-50"
          >
            {loading ? "Saving…" : "Confirm escalation"}
          </button>
          <button
            type="button"
            disabled={loading}
            onClick={() => {
              setMode("idle");
              setError(null);
            }}
            className="rounded-md border border-neutral-300 px-2 py-1 text-xs text-neutral-700"
          >
            Cancel
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="flex flex-wrap items-center gap-2">
      <button
        type="button"
        disabled={loading}
        onClick={() => submit("dismissed", "")}
        className="rounded-md border border-neutral-300 px-2 py-1 text-xs font-medium text-neutral-700 hover:bg-neutral-50 disabled:opacity-50"
      >
        {loading ? "…" : "Dismiss"}
      </button>
      <button
        type="button"
        disabled={loading}
        onClick={() => setMode("escalate")}
        className="rounded-md border border-red-300 bg-red-50 px-2 py-1 text-xs font-medium text-red-800 hover:bg-red-100 disabled:opacity-50"
      >
        Escalate
      </button>
      {error && <span className="text-xs text-red-600">{error}</span>}
    </div>
  );
}
