import { redirect } from "next/navigation";
import { ApiError } from "@/lib/session";
import { getMyMenus } from "@/lib/menus";
import { SidebarNav } from "@/components/sidebar-nav";
import { LogoutButton } from "@/components/logout-button";

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  let menus;
  try {
    menus = await getMyMenus();
  } catch (err) {
    // Covers both "no session" and "session token the API rejected"
    // (expired/invalid) — proxy.ts only checks the cookie exists, not that
    // it's still valid, so this is the real auth boundary for rendering.
    if (err instanceof ApiError && err.status === 401) redirect("/login");
    throw err;
  }

  return (
    <div className="flex min-h-screen">
      <aside className="flex w-64 shrink-0 flex-col border-r border-neutral-200 bg-neutral-50 p-4">
        <div className="mb-6 px-2">
          <span className="text-lg font-semibold text-neutral-900">
            OrderxPay
          </span>
          <span className="ml-1 text-xs text-neutral-400">Back Office</span>
        </div>
        <SidebarNav items={menus} />
        <div className="mt-auto pt-4">
          <LogoutButton />
        </div>
      </aside>
      <main className="flex-1 p-8">{children}</main>
    </div>
  );
}
