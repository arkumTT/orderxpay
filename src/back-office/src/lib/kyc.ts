import "server-only";
import { apiFetchServer } from "./session";
import type { KYCSubmissionWithMerchant, KYCTierLimit } from "./types";

export function listKYCSubmissions(params?: {
  status?: string;
}): Promise<KYCSubmissionWithMerchant[]> {
  const query = params?.status
    ? `?status=${encodeURIComponent(params.status)}`
    : "";
  return apiFetchServer<KYCSubmissionWithMerchant[]>(
    `/api/v1/admin/kyc-submissions${query}`,
  );
}

export function listKYCTierLimits(): Promise<KYCTierLimit[]> {
  return apiFetchServer<KYCTierLimit[]>("/api/v1/admin/kyc-tier-limits");
}
