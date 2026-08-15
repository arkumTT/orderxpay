"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

function isoDate(d: Date) {
  return d.toISOString().slice(0, 10);
}

function daysAgo(n: number) {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() - n);
  return isoDate(d);
}

const PRESETS = [
  { label: "Last 7 days", days: 7 },
  { label: "Last 30 days", days: 30 },
  { label: "Last 90 days", days: 90 },
];

const ACTOR_TYPES = [
  { value: "", label: "All actors" },
  { value: "user", label: "Back-office user" },
  { value: "system", label: "System" },
  { value: "merchant", label: "Merchant" },
  { value: "staff", label: "Staff" },
];

export function AuditLogFilters({
  periodStart,
  periodEnd,
  targetEntity,
  action,
  actorType,
  targetEntities,
}: {
  periodStart: string;
  periodEnd: string;
  targetEntity: string;
  action: string;
  actorType: string;
  targetEntities: string[];
}) {
  const router = useRouter();
  const [start, setStart] = useState(periodStart);
  const [end, setEnd] = useState(periodEnd);
  const [entity, setEntity] = useState(targetEntity);
  const [actionText, setActionText] = useState(action);
  const [actor, setActor] = useState(actorType);

  function apply(overrides?: { start?: string; end?: string }) {
    const query = new URLSearchParams();
    query.set("period_start", overrides?.start ?? start);
    query.set("period_end", overrides?.end ?? end);
    if (entity) query.set("target_entity", entity);
    if (actionText) query.set("action", actionText);
    if (actor) query.set("actor_type", actor);
    router.push(`/audit-log?${query.toString()}`);
  }

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        apply();
      }}
      className="flex flex-wrap items-end gap-3 rounded-lg border border-neutral-200 p-4"
    >
      <div className="space-y-1">
        <label className="text-xs text-neutral-500" htmlFor="al-start">
          From
        </label>
        <input
          id="al-start"
          type="date"
          value={start}
          onChange={(e) => setStart(e.target.value)}
          className="rounded-md border border-neutral-300 px-3 py-2 text-sm"
        />
      </div>
      <div className="space-y-1">
        <label className="text-xs text-neutral-500" htmlFor="al-end">
          To
        </label>
        <input
          id="al-end"
          type="date"
          value={end}
          onChange={(e) => setEnd(e.target.value)}
          className="rounded-md border border-neutral-300 px-3 py-2 text-sm"
        />
      </div>
      <div className="space-y-1">
        <label className="text-xs text-neutral-500" htmlFor="al-entity">
          Target entity
        </label>
        <select
          id="al-entity"
          value={entity}
          onChange={(e) => setEntity(e.target.value)}
          className="rounded-md border border-neutral-300 px-3 py-2 text-sm"
        >
          <option value="">All entities</option>
          {targetEntities.map((t) => (
            <option key={t} value={t}>
              {t}
            </option>
          ))}
        </select>
      </div>
      <div className="space-y-1">
        <label className="text-xs text-neutral-500" htmlFor="al-actor">
          Actor type
        </label>
        <select
          id="al-actor"
          value={actor}
          onChange={(e) => setActor(e.target.value)}
          className="rounded-md border border-neutral-300 px-3 py-2 text-sm"
        >
          {ACTOR_TYPES.map((a) => (
            <option key={a.value} value={a.value}>
              {a.label}
            </option>
          ))}
        </select>
      </div>
      <div className="min-w-[180px] flex-1 space-y-1">
        <label className="text-xs text-neutral-500" htmlFor="al-action">
          Action contains
        </label>
        <input
          id="al-action"
          type="text"
          value={actionText}
          onChange={(e) => setActionText(e.target.value)}
          placeholder="e.g. kyc.review"
          className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm"
        />
      </div>
      <button
        type="submit"
        className="rounded-md bg-neutral-900 px-4 py-2 text-sm font-medium text-white"
      >
        Apply
      </button>
      <div className="flex gap-2">
        {PRESETS.map((p) => (
          <button
            key={p.label}
            type="button"
            onClick={() => {
              const newStart = daysAgo(p.days);
              const newEnd = daysAgo(0);
              setStart(newStart);
              setEnd(newEnd);
              apply({ start: newStart, end: newEnd });
            }}
            className="rounded-md border border-neutral-300 px-2 py-1 text-xs text-neutral-700 hover:bg-neutral-50"
          >
            {p.label}
          </button>
        ))}
      </div>
    </form>
  );
}
