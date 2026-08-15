import { getAuditLog } from "@/lib/audit-log";
import { ApiError } from "@/lib/session";
import { AuditLogFilters } from "./audit-log-filters";
import { AuditLogRow } from "./audit-log-row";

function firstParam(v: string | string[] | undefined): string | undefined {
  return Array.isArray(v) ? v[0] : v;
}

export default async function AuditLogPage(props: PageProps<"/audit-log">) {
  const searchParams = await props.searchParams;
  const periodStart = firstParam(searchParams.period_start);
  const periodEnd = firstParam(searchParams.period_end);
  const targetEntity = firstParam(searchParams.target_entity) ?? "";
  const action = firstParam(searchParams.action) ?? "";
  const actorType = firstParam(searchParams.actor_type) ?? "";

  let log;
  try {
    log = await getAuditLog({
      periodStart,
      periodEnd,
      targetEntity,
      action,
      actorType,
    });
  } catch (err) {
    if (err instanceof ApiError && err.status === 403) {
      return (
        <p className="text-sm text-neutral-500">
          You don&apos;t have permission to view the audit log (requires
          audit.view).
        </p>
      );
    }
    throw err;
  }

  return (
    <div className="space-y-6">
      <div>
        <div className="flex items-baseline gap-2">
          <h1 className="text-2xl font-semibold text-neutral-900">
            Audit Trail &amp; Compliance Logging
          </h1>
          <span className="text-xs font-mono text-neutral-400">
            Section 7.9
          </span>
        </div>
        <p className="text-sm text-neutral-500">
          Immutable log of every sensitive back-office action — who, what,
          and when — for {log.period_start} – {log.period_end}. Entries are
          never edited or deleted; this view is read-only.
        </p>
      </div>

      <AuditLogFilters
        periodStart={log.period_start}
        periodEnd={log.period_end}
        targetEntity={targetEntity}
        action={action}
        actorType={actorType}
        targetEntities={log.target_entities}
      />

      {log.entries.length === 0 ? (
        <p className="text-sm text-neutral-500">
          No audit log entries match this filter.
        </p>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-neutral-200">
          <table className="w-full text-sm">
            <thead className="bg-neutral-50 text-left text-xs uppercase tracking-wide text-neutral-500">
              <tr>
                <th className="px-4 py-2">When</th>
                <th className="px-4 py-2">Actor</th>
                <th className="px-4 py-2">Action</th>
                <th className="px-4 py-2">Target</th>
                <th className="px-4 py-2"></th>
              </tr>
            </thead>
            <tbody className="divide-y divide-neutral-100">
              {log.entries.map((entry) => (
                <AuditLogRow key={entry.id} entry={entry} />
              ))}
            </tbody>
          </table>
        </div>
      )}
      {log.entries.length >= 200 && (
        <p className="text-xs text-neutral-400">
          Showing the most recent 200 entries in this period — narrow the
          date range or filters to see more specific results.
        </p>
      )}
    </div>
  );
}
