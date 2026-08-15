import "server-only";
import { apiFetchServer } from "./session";
import type { ReportingResponse } from "./types";

export function getReporting(params?: {
  periodStart?: string;
  periodEnd?: string;
}): Promise<ReportingResponse> {
  const query = new URLSearchParams();
  if (params?.periodStart) query.set("period_start", params.periodStart);
  if (params?.periodEnd) query.set("period_end", params.periodEnd);
  const qs = query.toString();
  return apiFetchServer<ReportingResponse>(
    `/api/v1/admin/reporting${qs ? `?${qs}` : ""}`,
  );
}
