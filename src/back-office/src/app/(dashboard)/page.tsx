import Link from "next/link";
import { getMyMenus, flattenMenus } from "@/lib/menus";

export default async function DashboardHome() {
  const menus = await getMyMenus();
  const links = flattenMenus(menus).filter((m) => m.path && m.path !== "/");

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-semibold text-neutral-900">Overview</h1>
      <p className="max-w-2xl text-sm text-neutral-500">
        OrderxPay Back Office — internal admin platform for merchant
        lifecycle management, settlement oversight, integrations
        configuration, pricing control, and business reporting
        (architecture doc, Section 7). The cards below reflect what your
        role actually has access to.
      </p>
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
        {links.map((item) => (
          <Link
            key={item.id}
            href={item.path!}
            className="rounded-lg border border-neutral-200 p-4 text-sm hover:border-neutral-400"
          >
            <div className="font-medium text-neutral-900">{item.label}</div>
            <div className="mt-1 font-mono text-xs text-neutral-400">
              {item.path}
            </div>
          </Link>
        ))}
      </div>
    </div>
  );
}
