import "server-only";
import { apiFetchServer } from "./session";
import type { DisputeDetail, DisputeWithContext } from "./types";

export function listDisputes(params?: {
  status?: string;
}): Promise<DisputeWithContext[]> {
  const query = params?.status
    ? `?status=${encodeURIComponent(params.status)}`
    : "";
  return apiFetchServer<DisputeWithContext[]>(
    `/api/v1/admin/disputes${query}`,
  );
}

export function getDispute(id: string): Promise<DisputeDetail> {
  return apiFetchServer<DisputeDetail>(`/api/v1/admin/disputes/${id}`);
}
