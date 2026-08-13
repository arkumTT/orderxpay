import { notFound } from "next/navigation";
import { getMerchant } from "@/lib/merchants";
import { formatPesewas } from "@/lib/money";
import { ApiError } from "@/lib/session";

const ALLOCATION_LABEL: Record<string, string> = {
  customer_only: "Customer pays the service charge",
  merchant_only: "Merchant absorbs the service charge",
  split: "Split between customer and merchant",
};

export default async function MerchantDetailPage(
  props: PageProps<"/merchants/[id]">,
) {
  const { id } = await props.params;

  let merchant;
  try {
    merchant = await getMerchant(id);
  } catch (err) {
    if (err instanceof ApiError && err.status === 404) notFound();
    throw err;
  }

  return (
    <div className="max-w-2xl space-y-6">
      <div>
        <div className="flex items-baseline gap-2">
          <h1 className="text-2xl font-semibold text-neutral-900">{merchant.business_name}</h1>
          <span className="text-xs font-mono text-neutral-400">Section 7.1</span>
        </div>
        {merchant.category && <p className="text-sm text-neutral-500">{merchant.category}</p>}
      </div>

      <dl className="grid grid-cols-2 gap-4 rounded-lg border border-neutral-200 p-4 text-sm sm:grid-cols-3">
        <div>
          <dt className="text-neutral-400">Status</dt>
          <dd className="font-medium text-neutral-900 capitalize">{merchant.status}</dd>
        </div>
        <div>
          <dt className="text-neutral-400">KYC Tier</dt>
          <dd className="font-medium text-neutral-900">Tier {merchant.kyc_tier}</dd>
        </div>
        <div>
          <dt className="text-neutral-400">Phone</dt>
          <dd className="font-medium text-neutral-900">{merchant.phone}</dd>
        </div>
        <div>
          <dt className="text-neutral-400">Payout schedule</dt>
          <dd className="font-medium text-neutral-900 capitalize">{merchant.payout_schedule.replace("_", " ")}</dd>
        </div>
        <div>
          <dt className="text-neutral-400">Payout min. threshold</dt>
          <dd className="font-medium text-neutral-900">{formatPesewas(merchant.payout_min_threshold_pesewas)}</dd>
        </div>
        <div>
          <dt className="text-neutral-400">Joined</dt>
          <dd className="font-medium text-neutral-900">
            {new Date(merchant.created_at).toLocaleDateString("en-GH", { day: "2-digit", month: "short", year: "numeric" })}
          </dd>
        </div>
      </dl>

      <div className="rounded-lg border border-neutral-200 p-4 text-sm">
        <h2 className="mb-1 font-medium text-neutral-900">Fee allocation</h2>
        <p className="text-neutral-600">
          {ALLOCATION_LABEL[merchant.service_charge_allocation]}
          {merchant.service_charge_allocation === "split" && merchant.service_charge_split_bps != null
            ? ` — customer pays ${(merchant.service_charge_split_bps / 100).toFixed(1)}% of the commission`
            : ""}
        </p>
      </div>

      {/* TODO: catalog snapshot, transaction/payout history, notes/flags
          (Section 7.1), and the suspend/KYC-review actions — those are
          state-changing calls and need an authenticated server-side proxy
          route (same pattern as /api/auth/login) since the session token
          is httpOnly and unreachable from client JS. */}
      <div className="rounded-lg border border-dashed border-neutral-300 p-6 text-center text-sm text-neutral-400">
        Catalog snapshot, transaction/payout history, and suspend/KYC
        actions not yet wired up.
      </div>
    </div>
  );
}
