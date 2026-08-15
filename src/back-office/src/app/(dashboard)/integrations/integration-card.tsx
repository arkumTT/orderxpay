"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Integration } from "@/lib/types";

function formatDate(d: string) {
  return new Date(d).toLocaleDateString("en-GH", {
    day: "2-digit",
    month: "short",
    year: "numeric",
  });
}

export function IntegrationCard({ integration }: { integration: Integration }) {
  const router = useRouter();
  const [secretValue, setSecretValue] = useState("");
  const [notes, setNotes] = useState(integration.notes ?? "");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [rotated, setRotated] = useState(false);

  async function rotateSecret(e: React.FormEvent) {
    e.preventDefault();
    if (!secretValue) return;
    setLoading(true);
    setError(null);
    setRotated(false);
    try {
      const res = await fetch(`/api/integrations/${integration.provider_key}/secret`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ secret_value: secretValue }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error ?? "failed to rotate secret");
      setSecretValue("");
      setRotated(true);
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "something went wrong");
    } finally {
      setLoading(false);
    }
  }

  async function saveNotes() {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`/api/integrations/${integration.provider_key}/notes`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ notes }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error ?? "failed to save notes");
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
          <div className="font-medium text-neutral-900">
            {integration.category}
          </div>
          <div className="text-xs text-neutral-400">
            {integration.provider_key}
          </div>
        </div>
        {integration.built ? (
          <span
            className={`shrink-0 rounded-full px-3 py-1 text-xs font-medium ${
              integration.has_secret
                ? "bg-green-100 text-green-800"
                : "bg-amber-100 text-amber-800"
            }`}
          >
            {integration.has_secret ? "Configured" : "Not configured"}
          </span>
        ) : (
          <span className="shrink-0 rounded-full bg-neutral-100 px-3 py-1 text-xs font-medium text-neutral-500">
            Not built
          </span>
        )}
      </div>

      {integration.built ? (
        <>
          {integration.secret_updated_at && (
            <p className="mt-2 text-xs text-neutral-400">
              Credential last rotated {formatDate(integration.secret_updated_at)}
            </p>
          )}
          <form onSubmit={rotateSecret} className="mt-3 flex gap-2">
            <input
              type="password"
              value={secretValue}
              onChange={(e) => {
                setSecretValue(e.target.value);
                setRotated(false);
              }}
              placeholder={integration.has_secret ? "New secret key…" : "Secret key…"}
              className="flex-1 rounded-md border border-neutral-300 px-3 py-2 text-sm"
            />
            <button
              type="submit"
              disabled={loading || !secretValue}
              className="rounded-md bg-neutral-900 px-3 py-2 text-sm font-medium text-white disabled:opacity-50"
            >
              {loading ? "Saving…" : "Rotate"}
            </button>
          </form>
          <p className="mt-1 text-xs text-neutral-400">
            Never displayed again once saved — this takes effect immediately,
            no restart needed.
          </p>
          {rotated && (
            <p className="mt-1 text-xs text-green-700">Credential rotated.</p>
          )}
        </>
      ) : (
        <p className="mt-2 text-xs text-neutral-400">
          No integration code exists for this provider yet — notes only.
        </p>
      )}

      <div className="mt-3">
        <label className="text-xs text-neutral-500">Notes</label>
        <textarea
          value={notes}
          onChange={(e) => setNotes(e.target.value)}
          onBlur={saveNotes}
          rows={2}
          placeholder="Vendor decisions, credentials location, anything worth recording"
          className="mt-1 w-full rounded-md border border-neutral-300 px-2 py-1 text-xs"
        />
      </div>
      {error && <p className="mt-2 text-xs text-red-600">{error}</p>}
    </div>
  );
}
