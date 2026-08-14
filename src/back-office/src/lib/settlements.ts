import "server-only";
import { apiFetchServer } from "./session";
import type { SettlementWithMerchant } from "./types";

export function listAllSettlements(params?: {
  status?: string;
}): Promise<SettlementWithMerchant[]> {
  const query = params?.status
    ? `?status=${encodeURIComponent(params.status)}`
    : "";
  return apiFetchServer<SettlementWithMerchant[]>(
    `/api/v1/admin/settlements${query}`,
  );
}
