"use client";

import { useState } from "react";
import type { AuditLogEntry } from "@/lib/types";

function formatDateTime(d: string) {
  return new Date(d).toLocaleString("en-GH", {
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function actorLabel(entry: AuditLogEntry) {
  if (entry.actor_type === "system") return "System";
  if (entry.actor_name) return entry.actor_name;
  if (entry.actor_email) return entry.actor_email;
  return `${entry.actor_type} (${entry.actor_id.slice(0, 8)})`;
}

export function AuditLogRow({ entry }: { entry: AuditLogEntry }) {
  const [expanded, setExpanded] = useState(false);
  const hasState = entry.before_state || entry.after_state;

  return (
    <>
      <tr
        className={`hover:bg-neutral-50 ${hasState ? "cursor-pointer" : ""}`}
        onClick={() => hasState && setExpanded((v) => !v)}
      >
        <td className="whitespace-nowrap px-4 py-2 text-neutral-600">
          {formatDateTime(entry.created_at)}
        </td>
        <td className="px-4 py-2">
          <div className="text-neutral-900">{actorLabel(entry)}</div>
          <div className="text-xs text-neutral-400">{entry.actor_type}</div>
        </td>
        <td className="px-4 py-2 font-mono text-xs text-neutral-700">
          {entry.action}
        </td>
        <td className="px-4 py-2 text-neutral-600">
          {entry.target_entity}
          {entry.target_id && (
            <span className="ml-1 font-mono text-xs text-neutral-400">
              {entry.target_id.slice(0, 8)}
            </span>
          )}
        </td>
        <td className="px-4 py-2 text-right text-xs text-neutral-400">
          {hasState ? (expanded ? "Hide" : "Details") : "—"}
        </td>
      </tr>
      {expanded && hasState && (
        <tr>
          <td colSpan={5} className="bg-neutral-50 px-4 py-3">
            <div className="grid gap-3 sm:grid-cols-2">
              <div>
                <div className="mb-1 text-xs font-semibold uppercase tracking-wide text-neutral-500">
                  Before
                </div>
                <pre className="overflow-x-auto rounded-md border border-neutral-200 bg-white p-2 text-xs text-neutral-700">
                  {entry.before_state
                    ? JSON.stringify(entry.before_state, null, 2)
                    : "—"}
                </pre>
              </div>
              <div>
                <div className="mb-1 text-xs font-semibold uppercase tracking-wide text-neutral-500">
                  After
                </div>
                <pre className="overflow-x-auto rounded-md border border-neutral-200 bg-white p-2 text-xs text-neutral-700">
                  {entry.after_state
                    ? JSON.stringify(entry.after_state, null, 2)
                    : "—"}
                </pre>
              </div>
            </div>
          </td>
        </tr>
      )}
    </>
  );
}
