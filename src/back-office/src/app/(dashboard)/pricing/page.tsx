import { getGlobalFeeRule, listFeeRuleOverrides, listFeatureFlags } from "@/lib/pricing";
import { listMerchants } from "@/lib/merchants";
import { ApiError } from "@/lib/session";
import { GlobalFeeForm } from "./global-fee-form";
import { MerchantOverrides } from "./merchant-overrides";
import { FeatureFlagCard } from "./feature-flag-card";
import { CsvExportButton } from "./csv-export-button";

export default async function PricingPage() {
  let globalRule, overrides, flags, merchants;
  try {
    [overrides, flags, merchants] = await Promise.all([
      listFeeRuleOverrides(),
      listFeatureFlags(),
      listMerchants(),
    ]);
    try {
      globalRule = await getGlobalFeeRule();
    } catch (err) {
      if (err instanceof ApiError && err.status === 404) {
        globalRule = null;
      } else {
        throw err;
      }
    }
  } catch (err) {
    if (err instanceof ApiError && err.status === 403) {
      return (
        <p className="text-sm text-neutral-500">
          You don&apos;t have permission to view pricing (requires
          pricing.view).
        </p>
      );
    }
    throw err;
  }

  return (
    <div className="space-y-6">
      <div>
        <div className="flex items-baseline gap-2">
          <h1 className="text-2xl font-semibold text-neutral-900">
            Pricing, Commission &amp; Feature Configuration
          </h1>
          <span className="text-xs font-mono text-neutral-400">
            Section 7.4
          </span>
        </div>
        <p className="text-sm text-neutral-500">
          The global default commission and allocation, per-merchant
          overrides, and feature flags for rolling a module out to a subset
          of merchants before a global launch.
        </p>
      </div>

      <div>
        <h2 className="mb-2 text-sm font-semibold text-neutral-700">
          Global default
        </h2>
        <GlobalFeeForm rule={globalRule} />
      </div>

      <div>
        <div className="mb-2 flex flex-wrap items-center justify-between gap-3">
          <h2 className="text-sm font-semibold text-neutral-700">
            Merchant-specific overrides
          </h2>
          <CsvExportButton overrides={overrides} />
        </div>
        <MerchantOverrides overrides={overrides} merchants={merchants} />
      </div>

      <div>
        <h2 className="mb-2 text-sm font-semibold text-neutral-700">
          Feature flags
        </h2>
        <div className="grid gap-3 sm:grid-cols-2">
          {flags.map((f) => (
            <FeatureFlagCard key={f.id} flag={f} merchants={merchants} />
          ))}
        </div>
      </div>
    </div>
  );
}
