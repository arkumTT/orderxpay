import "server-only";
import { apiFetchServer } from "./session";
import type { KYCSubmissionWithMerchant } from "./types";

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
