"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import type { DeliveryProvider } from "@/lib/types";

function AddProviderForm() {
  const router = useRouter();
  const [key, setKey] = useState("");
  const [name, setName] = useState("");
  const [template, setTemplate] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError(null);
    try {
      const res = await fetch("/api/delivery-providers", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          key,
          name,
          deep_link_template: template,
        }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error ?? "failed to add provider");
      setKey("");
      setName("");
      setTemplate("");
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
        <label className="text-xs text-neutral-500" htmlFor="dp-key">
          Key
        </label>
        <input
          id="dp-key"
          required
          value={key}
          onChange={(e) => setKey(e.target.value)}
          placeholder="bolt_send"
          className="rounded-md border border-neutral-300 px-3 py-2 text-sm"
        />
      </div>
      <div className="space-y-1">
        <label className="text-xs text-neutral-500" htmlFor="dp-name">
          Name
        </label>
        <input
          id="dp-name"
          required
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="Bolt Send"
          className="rounded-md border border-neutral-300 px-3 py-2 text-sm"
        />
      </div>
      <div className="min-w-[260px] flex-1 space-y-1">
        <label className="text-xs text-neutral-500" htmlFor="dp-template">
          Deep-link template
        </label>
        <input
          id="dp-template"
          required
          value={template}
          onChange={(e) => setTemplate(e.target.value)}
          placeholder="https://bolt.eu/send?pickup={pickup}&dropoff={dropoff}"
          className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm"
        />
      </div>
      <button
        type="submit"
        disabled={loading || !key || !name || !template}
        className="rounded-md bg-neutral-900 px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
      >
        {loading ? "Adding…" : "Add provider"}
      </button>
      {error && <p className="w-full text-sm text-red-600">{error}</p>}
    </form>
  );
}

function ProviderRow({ provider }: { provider: DeliveryProvider }) {
  const router = useRouter();
  const [name, setName] = useState(provider.name);
  const [template, setTemplate] = useState(provider.deep_link_template);
  const [notes, setNotes] = useState(provider.notes ?? "");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function save(overrides?: { status?: string }) {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`/api/delivery-providers/${provider.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name,
          deep_link_template: template,
          status: overrides?.status ?? provider.status,
          notes,
        }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error ?? "failed to save");
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "something went wrong");
    } finally {
      setLoading(false);
    }
  }

  async function remove() {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`/api/delivery-providers/${provider.id}`, {
        method: "DELETE",
      });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data.error ?? "failed to delete");
      }
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "something went wrong");
      setLoading(false);
    }
  }

  return (
    <tr className="hover:bg-neutral-50">
      <td className="px-4 py-2 align-top text-xs text-neutral-400">
        {provider.key}
      </td>
      <td className="px-4 py-2 align-top">
        <input
          value={name}
          onChange={(e) => setName(e.target.value)}
          className="w-full rounded-md border border-neutral-300 px-2 py-1 text-sm"
        />
      </td>
      <td className="px-4 py-2 align-top">
        <input
          value={template}
          onChange={(e) => setTemplate(e.target.value)}
          className="w-full rounded-md border border-neutral-300 px-2 py-1 font-mono text-xs"
        />
      </td>
      <td className="px-4 py-2 align-top">
        <input
          value={notes}
          onChange={(e) => setNotes(e.target.value)}
          className="w-full rounded-md border border-neutral-300 px-2 py-1 text-xs"
        />
      </td>
      <td className="px-4 py-2 align-top">
        <span
          className={`rounded-full px-2 py-0.5 text-xs font-medium ${
            provider.status === "active"
              ? "bg-green-100 text-green-800"
              : "bg-neutral-100 text-neutral-500"
          }`}
        >
          {provider.status}
        </span>
      </td>
      <td className="px-4 py-2 align-top">
        <div className="flex flex-wrap gap-1">
          <button
            type="button"
            disabled={loading}
            onClick={() => save()}
            className="rounded-md border border-neutral-300 px-2 py-1 text-xs text-neutral-700 hover:bg-neutral-50 disabled:opacity-50"
          >
            Save
          </button>
          <button
            type="button"
            disabled={loading}
            onClick={() =>
              save({ status: provider.status === "active" ? "inactive" : "active" })
            }
            className="rounded-md border border-neutral-300 px-2 py-1 text-xs text-neutral-700 hover:bg-neutral-50 disabled:opacity-50"
          >
            {provider.status === "active" ? "Deactivate" : "Activate"}
          </button>
          <button
            type="button"
            disabled={loading}
            onClick={remove}
            className="rounded-md border border-red-300 px-2 py-1 text-xs text-red-700 hover:bg-red-50 disabled:opacity-50"
          >
            Delete
          </button>
        </div>
        {error && <p className="mt-1 text-xs text-red-600">{error}</p>}
      </td>
    </tr>
  );
}

export function DeliveryProviderManager({
  providers,
}: {
  providers: DeliveryProvider[];
}) {
  return (
    <div className="space-y-3">
      <AddProviderForm />
      {providers.length === 0 ? (
        <p className="text-sm text-neutral-500">No delivery providers yet.</p>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-neutral-200">
          <table className="w-full text-sm">
            <thead className="bg-neutral-50 text-left text-xs uppercase tracking-wide text-neutral-500">
              <tr>
                <th className="px-4 py-2">Key</th>
                <th className="px-4 py-2">Name</th>
                <th className="px-4 py-2">Deep-link template</th>
                <th className="px-4 py-2">Notes</th>
                <th className="px-4 py-2">Status</th>
                <th className="px-4 py-2">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-neutral-100">
              {providers.map((p) => (
                <ProviderRow key={p.id} provider={p} />
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
