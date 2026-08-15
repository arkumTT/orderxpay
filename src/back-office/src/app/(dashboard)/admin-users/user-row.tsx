"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import type { AdminUser, Role } from "@/lib/types";

const STATUS_STYLES: Record<string, string> = {
  active: "bg-green-100 text-green-800",
  suspended: "bg-red-100 text-red-800",
};

function formatDate(d: string) {
  return new Date(d).toLocaleDateString("en-GH", {
    day: "2-digit",
    month: "short",
    year: "numeric",
  });
}

export function UserRow({
  user,
  allRoles,
}: {
  user: AdminUser & { roles: Role[] };
  allRoles: Role[];
}) {
  const router = useRouter();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [roleToAdd, setRoleToAdd] = useState("");

  const assignedIds = new Set(user.roles.map((r) => r.id));
  const availableRoles = allRoles.filter((r) => !assignedIds.has(r.id));

  async function toggleStatus() {
    setLoading(true);
    setError(null);
    try {
      const next = user.status === "active" ? "suspended" : "active";
      const res = await fetch(`/api/admin-users/${user.id}/status`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ status: next }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error ?? "failed to update status");
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "something went wrong");
    } finally {
      setLoading(false);
    }
  }

  async function addRole() {
    if (!roleToAdd) return;
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`/api/admin-users/${user.id}/roles`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ role_id: roleToAdd }),
      });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data.error ?? "failed to assign role");
      }
      setRoleToAdd("");
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "something went wrong");
    } finally {
      setLoading(false);
    }
  }

  async function removeRole(roleId: string) {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`/api/admin-users/${user.id}/roles/${roleId}`, {
        method: "DELETE",
      });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data.error ?? "failed to remove role");
      }
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "something went wrong");
    } finally {
      setLoading(false);
    }
  }

  return (
    <tr className="hover:bg-neutral-50">
      <td className="px-4 py-3 align-top">
        <div className="font-medium text-neutral-900">{user.name}</div>
        <div className="text-xs text-neutral-500">{user.email}</div>
        <div className="text-xs text-neutral-400">
          Joined {formatDate(user.created_at)}
        </div>
      </td>
      <td className="px-4 py-3 align-top">
        <div className="flex flex-wrap gap-1">
          {user.roles.length === 0 && (
            <span className="text-xs text-neutral-400">No roles</span>
          )}
          {user.roles.map((r) => (
            <span
              key={r.id}
              className="flex items-center gap-1 rounded-full bg-neutral-100 px-2 py-0.5 text-xs font-medium text-neutral-700"
            >
              {r.name}
              <button
                type="button"
                disabled={loading}
                onClick={() => removeRole(r.id)}
                className="text-neutral-400 hover:text-red-600 disabled:opacity-50"
                aria-label={`Remove ${r.name}`}
              >
                ×
              </button>
            </span>
          ))}
        </div>
        {availableRoles.length > 0 && (
          <div className="mt-2 flex gap-1">
            <select
              value={roleToAdd}
              onChange={(e) => setRoleToAdd(e.target.value)}
              className="rounded-md border border-neutral-300 px-1 py-0.5 text-xs"
            >
              <option value="">+ Add role…</option>
              {availableRoles.map((r) => (
                <option key={r.id} value={r.id}>
                  {r.name}
                </option>
              ))}
            </select>
            <button
              type="button"
              disabled={loading || !roleToAdd}
              onClick={addRole}
              className="rounded-md border border-neutral-300 px-2 py-0.5 text-xs text-neutral-700 hover:bg-neutral-50 disabled:opacity-50"
            >
              Add
            </button>
          </div>
        )}
      </td>
      <td className="px-4 py-3 align-top">
        <span
          className={`rounded-full px-2 py-0.5 text-xs font-medium ${STATUS_STYLES[user.status]}`}
        >
          {user.status}
        </span>
      </td>
      <td className="px-4 py-3 align-top">
        <button
          type="button"
          disabled={loading}
          onClick={toggleStatus}
          className="rounded-md border border-neutral-300 px-2 py-1 text-xs font-medium text-neutral-700 hover:bg-neutral-50 disabled:opacity-50"
        >
          {loading ? "…" : user.status === "active" ? "Suspend" : "Activate"}
        </button>
        {error && <p className="mt-1 text-xs text-red-600">{error}</p>}
      </td>
    </tr>
  );
}
