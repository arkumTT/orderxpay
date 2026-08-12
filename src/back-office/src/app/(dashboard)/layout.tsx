import Link from "next/link";
import { NAV_ITEMS } from "@/lib/nav";

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="flex min-h-screen">
      <aside className="w-64 shrink-0 border-r border-neutral-200 bg-neutral-50 p-4">
        <div className="mb-6 px-2">
          <span className="text-lg font-semibold text-neutral-900">
            OrderxPay
          </span>
          <span className="ml-1 text-xs text-neutral-400">Back Office</span>
        </div>
        <nav className="space-y-0.5">
          {NAV_ITEMS.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              className="block rounded-md px-2 py-1.5 text-sm text-neutral-600 hover:bg-neutral-200 hover:text-neutral-900"
            >
              {item.label}
            </Link>
          ))}
        </nav>
      </aside>
      <main className="flex-1 p-8">{children}</main>
    </div>
  );
}
