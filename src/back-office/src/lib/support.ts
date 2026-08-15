import "server-only";
import { apiFetchServer } from "./session";
import type { SupportSearchResponse, SupportTransactionDetail } from "./types";

export function searchSupport(query: string): Promise<SupportSearchResponse> {
  return apiFetchServer<SupportSearchResponse>(
    `/api/v1/admin/support/search?q=${encodeURIComponent(query)}`,
  );
}

export function getSupportTransaction(
  reference: string,
): Promise<SupportTransactionDetail> {
  return apiFetchServer<SupportTransactionDetail>(
    `/api/v1/admin/support/transactions/${encodeURIComponent(reference)}`,
  );
}
