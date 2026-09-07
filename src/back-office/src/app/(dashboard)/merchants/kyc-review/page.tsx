import Link from "next/link";
import { listKYCSubmissions } from "@/lib/kyc";
import { ApiError } from "@/lib/session";
import type { KYCSubmissionWithMerchant } from "@/lib/types";
import { KYCReviewActions } from "./review-actions";
import { CsvExportButton } from "./csv-export-button";

const STATUS_STYLES: Record<string, string> = {
  pending: "bg-amber-100 text-amber-800",
  more_info_requested: "bg-blue-100 text-blue-800",
  approved: "bg-green-100 text-green-800",
  rejected: "bg-red-100 text-red-800",
};

function formatDate(d: string) {
  return new Date(d).toLocaleDateString("en-GH", {
    day: "2-digit",
    month: "short",
    year: "numeric",
  });
}

function SubmissionRow({
  s,
  showActions,
}: {
  s: KYCSubmissionWithMerchant;
  showActions: boolean;
}) {
  return (
    <tr className="hover:bg-neutral-50">
      <td className="px-4 py-3 align-top">
        <Link
          href={`/merchants/${s.merchant_id}`}
          className="font-medium text-neutral-900 hover:underline"
        >
          {s.merchant_business_name}
        </Link>
        <div className="text-xs text-neutral-400">{formatDate(s.created_at)}</div>
      </td>
      <td className="px-4 py-3 align-top text-neutral-600">
        <div>Ghana Card: {s.ghana_card_number}</div>
        {s.business_reg_number && <div>Biz reg: {s.business_reg_number}</div>}
        {s.notes && <div className="text-xs text-neutral-400">{s.notes}</div>}
      </td>
      <td className="px-4 py-3 align-top">
        {s.selfie_photo_path ? (
          <a
            href={`/api/kyc-submissions/${s.id}/selfie-photo`}
            target="_blank"
            rel="noopener noreferrer"
            title="Open full size"
          >
            {/* eslint-disable-next-line @next/next/no-img-element -- the
                source is a same-origin proxy route (see
                app/api/kyc-submissions/[id]/selfie-photo/route.ts), not an
                external/remote host next/image would need configuring for. */}
            <img
              src={`/api/kyc-submissions/${s.id}/selfie-photo`}
              alt="Liveness-check selfie"
              className="h-16 w-16 rounded-md border border-neutral-200 object-cover"
            />
          </a>
        ) : (
          <span className="text-xs text-neutral-400">No selfie</span>
        )}
      </td>
      <td className="px-4 py-3 align-top">
        <span
          className={`rounded-full px-2 py-0.5 text-xs font-medium ${STATUS_STYLES[s.status]}`}
        >
          {s.status.replace("_", " ")}
        </span>
        {s.reviewer_notes && (
          <div className="mt-1 text-xs text-neutral-500">{s.reviewer_notes}</div>
        )}
      </td>
      <td className="px-4 py-3 align-top">
        {showActions ? (
          <KYCReviewActions
            submissionId={s.id}
            status={s.status as "pending" | "more_info_requested"}
          />
        ) : (
          <span className="text-xs text-neutral-400">
            {s.reviewed_at ? formatDate(s.reviewed_at) : "—"}
          </span>
        )}
      </td>
    </tr>
  );
}

export default async function KycReviewPage() {
  let submissions: KYCSubmissionWithMerchant[];
  try {
    submissions = await listKYCSubmissions();
  } catch (err) {
    if (err instanceof ApiError && err.status === 403) {
      return (
        <p className="text-sm text-neutral-500">
          You don&apos;t have permission to review KYC submissions (requires
          merchants.kyc_review).
        </p>
      );
    }
    throw err;
  }

  const queue = submissions.filter(
    (s) => s.status === "pending" || s.status === "more_info_requested",
  );
  const resolved = submissions.filter(
    (s) => s.status === "approved" || s.status === "rejected",
  );

  return (
    <div className="space-y-6">
      <div>
        <div className="flex items-baseline gap-2">
          <h1 className="text-2xl font-semibold text-neutral-900">
            KYC Review Queue
          </h1>
          <span className="text-xs font-mono text-neutral-400">
            Section 7.1
          </span>
        </div>
        <p className="text-sm text-neutral-500">
          Ghana Card and business registration details submitted for Tier 1
          verification, alongside a liveness-check selfie captured on-device
          (blink + head-turn challenge — see the merchant app). This stops a
          static printed/screen photo, not a sophisticated pre-recorded
          video; weigh that when a selfie looks off. Approving immediately
          unlocks payouts for that merchant.
        </p>
      </div>

      <div className="flex justify-end">
        <CsvExportButton submissions={submissions} />
      </div>

      <div>
        <h2 className="mb-2 text-sm font-semibold text-neutral-700">
          Queue ({queue.length})
        </h2>
        {queue.length === 0 ? (
          <p className="text-sm text-neutral-500">Nothing waiting on review.</p>
        ) : (
          <div className="overflow-x-auto rounded-lg border border-neutral-200">
            <table className="w-full text-sm">
              <thead className="bg-neutral-50 text-left text-xs uppercase tracking-wide text-neutral-500">
                <tr>
                  <th className="px-4 py-2">Merchant</th>
                  <th className="px-4 py-2">Submitted details</th>
                  <th className="px-4 py-2">Selfie</th>
                  <th className="px-4 py-2">Status</th>
                  <th className="px-4 py-2">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-neutral-100">
                {queue.map((s) => (
                  <SubmissionRow key={s.id} s={s} showActions />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {resolved.length > 0 && (
        <div>
          <h2 className="mb-2 text-sm font-semibold text-neutral-700">
            Resolved
          </h2>
          <div className="overflow-x-auto rounded-lg border border-neutral-200">
            <table className="w-full text-sm">
              <thead className="bg-neutral-50 text-left text-xs uppercase tracking-wide text-neutral-500">
                <tr>
                  <th className="px-4 py-2">Merchant</th>
                  <th className="px-4 py-2">Submitted details</th>
                  <th className="px-4 py-2">Selfie</th>
                  <th className="px-4 py-2">Status</th>
                  <th className="px-4 py-2">Reviewed</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-neutral-100">
                {resolved.map((s) => (
                  <SubmissionRow key={s.id} s={s} showActions={false} />
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
