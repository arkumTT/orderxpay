import "server-only";
import { apiFetchServer } from "./session";
import type { ReconciliationResponse } from "./types";

export function getReconciliation(params?: {
  periodStart?: string;
  periodEnd?: string;
}): Promise<ReconciliationResponse> {
  const query = new URLSearchParams();
  if (params?.periodStart) query.set("period_start", params.periodStart);
  if (params?.periodEnd) query.set("period_end", params.periodEnd);
  const qs = query.toString();
  return apiFetchServer<ReconciliationResponse>(
    `/api/v1/admin/reconciliation${qs ? `?${qs}` : ""}`,
  );
}
