import Link from "next/link";
import { listMerchants } from "@/lib/merchants";
import { ApiError } from "@/lib/session";

const STATUS_STYLES: Record<string, string> = {
  active: "bg-green-100 text-green-800",
  pending: "bg-amber-100 text-amber-800",
  restricted: "bg-orange-100 text-orange-800",
  suspended: "bg-red-100 text-red-800",
};

export default async function MerchantsPage() {
  let merchants;
  try {
    merchants = await listMerchants();
  } catch (err) {
    if (err instanceof ApiError && err.status === 403) {
      return (
        <p className="text-sm text-neutral-500">
          You don&apos;t have permission to view merchants (requires
          merchants.view).
        </p>
      );
    }
    throw err;
  }

  return (
    <div className="space-y-4">
      <div className="flex items-baseline gap-2">
        <h1 className="text-2xl font-semibold text-neutral-900">Merchants</h1>
        <span className="text-xs font-mono text-neutral-400">Section 7.1</span>
      </div>

      {merchants.length === 0 ? (
        <p className="text-sm text-neutral-500">No merchants yet.</p>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-neutral-200">
          <table className="w-full text-sm">
            <thead className="bg-neutral-50 text-left text-xs uppercase tracking-wide text-neutral-500">
              <tr>
                <th className="px-4 py-2">Business</th>
                <th className="px-4 py-2">Phone</th>
                <th className="px-4 py-2">KYC Tier</th>
                <th className="px-4 py-2">Status</th>
                <th className="px-4 py-2">Joined</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-neutral-100">
              {merchants.map((m) => (
                <tr key={m.id} className="hover:bg-neutral-50">
                  <td className="px-4 py-2">
                    <Link href={`/merchants/${m.id}`} className="font-medium text-neutral-900 hover:underline">
                      {m.business_name}
                    </Link>
                    {m.category && <div className="text-xs text-neutral-400">{m.category}</div>}
                  </td>
                  <td className="px-4 py-2 text-neutral-600">{m.phone}</td>
                  <td className="px-4 py-2 text-neutral-600">Tier {m.kyc_tier}</td>
                  <td className="px-4 py-2">
                    <span className={`rounded-full px-2 py-0.5 text-xs font-medium ${STATUS_STYLES[m.status]}`}>
                      {m.status}
                    </span>
                  </td>
                  <td className="px-4 py-2 text-neutral-500">
                    {new Date(m.created_at).toLocaleDateString("en-GH", { day: "2-digit", month: "short", year: "numeric" })}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
