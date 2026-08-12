import { NAV_ITEMS } from "@/lib/nav";
import Link from "next/link";

export default function DashboardHome() {
  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-semibold text-neutral-900">Overview</h1>
      <p className="max-w-2xl text-sm text-neutral-500">
        OrderxPay Back Office — internal admin platform for merchant
        lifecycle management, settlement oversight, integrations
        configuration, pricing control, and business reporting
        (architecture doc, Section 7).
      </p>
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
        {NAV_ITEMS.map((item) => (
          <Link
            key={item.href}
            href={item.href}
            className="rounded-lg border border-neutral-200 p-4 text-sm hover:border-neutral-400"
          >
            <div className="font-medium text-neutral-900">{item.label}</div>
            <div className="mt-1 font-mono text-xs text-neutral-400">
              Section {item.section}
            </div>
          </Link>
        ))}
      </div>
    </div>
  );
}
