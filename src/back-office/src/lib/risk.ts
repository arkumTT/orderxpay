import "server-only";
import { apiFetchServer } from "./session";
import type { RiskFlagWithMerchant } from "./types";

export function listRiskFlags(params?: {
  status?: string;
}): Promise<RiskFlagWithMerchant[]> {
  const query = params?.status
    ? `?status=${encodeURIComponent(params.status)}`
    : "";
  return apiFetchServer<RiskFlagWithMerchant[]>(
    `/api/v1/admin/risk/flags${query}`,
  );
}
