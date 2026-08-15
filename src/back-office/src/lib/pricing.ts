import "server-only";
import { apiFetchServer } from "./session";
import type { FeeRule, FeeRuleOverride, FeatureFlag } from "./types";

export function getGlobalFeeRule(): Promise<FeeRule> {
  return apiFetchServer<FeeRule>("/api/v1/admin/fee-rules/global");
}

export function listFeeRuleOverrides(): Promise<FeeRuleOverride[]> {
  return apiFetchServer<FeeRuleOverride[]>("/api/v1/admin/fee-rules/overrides");
}

export function listFeatureFlags(): Promise<FeatureFlag[]> {
  return apiFetchServer<FeatureFlag[]>("/api/v1/admin/feature-flags");
}
