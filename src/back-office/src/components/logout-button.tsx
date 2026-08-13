"use client";

import { useRouter } from "next/navigation";

export function LogoutButton() {
  const router = useRouter();

  async function handleLogout() {
    await fetch("/api/auth/logout", { method: "POST" });
    router.push("/login");
    router.refresh();
  }

  return (
    <button
      type="button"
      onClick={handleLogout}
      className="w-full rounded-md px-2 py-1.5 text-left text-sm text-neutral-500 hover:bg-neutral-200 hover:text-neutral-900"
    >
      Sign out
    </button>
  );
}
