import "server-only";
import { apiFetchServer } from "./session";
import type { AuditLogResponse } from "./types";

export function getAuditLog(params?: {
  periodStart?: string;
  periodEnd?: string;
  targetEntity?: string;
  action?: string;
  actorType?: string;
}): Promise<AuditLogResponse> {
  const query = new URLSearchParams();
  if (params?.periodStart) query.set("period_start", params.periodStart);
  if (params?.periodEnd) query.set("period_end", params.periodEnd);
  if (params?.targetEntity) query.set("target_entity", params.targetEntity);
  if (params?.action) query.set("action", params.action);
  if (params?.actorType) query.set("actor_type", params.actorType);
  const qs = query.toString();
  return apiFetchServer<AuditLogResponse>(
    `/api/v1/admin/audit-log${qs ? `?${qs}` : ""}`,
  );
}
