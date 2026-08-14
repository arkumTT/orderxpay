"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

type PendingAction = "rejected" | "more_info_requested" | null;

export function KYCReviewActions({
  submissionId,
  status,
}: {
  submissionId: string;
  status: "pending" | "more_info_requested";
}) {
  const router = useRouter();
  const [pendingAction, setPendingAction] = useState<PendingAction>(null);
  const [reason, setReason] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(status: string, reviewerNotes: string) {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`/api/kyc-submissions/${submissionId}/status`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ status, reviewer_notes: reviewerNotes }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error(data.error ?? "failed to update submission");
      }
      setPendingAction(null);
      setReason("");
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "something went wrong");
    } finally {
      setLoading(false);
    }
  }

  if (pendingAction) {
    const label =
      pendingAction === "rejected" ? "Reason for rejection" : "What's needed";
    return (
      <div className="space-y-2">
        <label className="block text-xs text-neutral-500">{label}</label>
        <textarea
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          rows={2}
          className="w-full rounded-md border border-neutral-300 px-2 py-1 text-xs"
          autoFocus
        />
        {error && <p className="text-xs text-red-600">{error}</p>}
        <div className="flex gap-2">
          <button
            type="button"
            disabled={loading || !reason.trim()}
            onClick={() => submit(pendingAction, reason.trim())}
            className="rounded-md bg-neutral-900 px-2 py-1 text-xs font-medium text-white disabled:opacity-50"
          >
            {loading ? "Saving…" : "Confirm"}
          </button>
          <button
            type="button"
            disabled={loading}
            onClick={() => {
              setPendingAction(null);
              setReason("");
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
        onClick={() => submit("approved", "")}
        className="rounded-md border border-green-300 bg-green-50 px-2 py-1 text-xs font-medium text-green-800 hover:bg-green-100 disabled:opacity-50"
      >
        {loading ? "…" : "Approve"}
      </button>
      {status === "pending" && (
        <button
          type="button"
          disabled={loading}
          onClick={() => setPendingAction("more_info_requested")}
          className="rounded-md border border-neutral-300 px-2 py-1 text-xs font-medium text-neutral-700 hover:bg-neutral-50 disabled:opacity-50"
        >
          Request more info
        </button>
      )}
      <button
        type="button"
        disabled={loading}
        onClick={() => setPendingAction("rejected")}
        className="rounded-md border border-red-300 bg-red-50 px-2 py-1 text-xs font-medium text-red-800 hover:bg-red-100 disabled:opacity-50"
      >
        Reject
      </button>
      {error && <span className="text-xs text-red-600">{error}</span>}
    </div>
  );
}
