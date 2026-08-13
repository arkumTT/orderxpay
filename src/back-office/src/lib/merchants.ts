import "server-only";
import { apiFetchServer } from "./session";
import type { Merchant } from "./types";

export function listMerchants(params?: { status?: string }): Promise<Merchant[]> {
  const query = params?.status ? `?status=${encodeURIComponent(params.status)}` : "";
  return apiFetchServer<Merchant[]>(`/api/v1/admin/merchants${query}`);
}

export function getMerchant(id: string): Promise<Merchant> {
  return apiFetchServer<Merchant>(`/api/v1/admin/merchants/${id}`);
}
