"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import type { MenuNode } from "@/lib/menus";

export function SidebarNav({ items }: { items: MenuNode[] }) {
  const pathname = usePathname();
  return (
    <nav className="space-y-0.5">
      {items.map((item) => (
        <MenuItem key={item.id} item={item} pathname={pathname} />
      ))}
    </nav>
  );
}

function MenuItem({
  item,
  pathname,
  depth = 0,
}: {
  item: MenuNode;
  pathname: string;
  depth?: number;
}) {
  const active = item.path === pathname;
  const indent = depth > 0 ? "ml-3" : "";

  return (
    <div>
      {item.path ? (
        <Link
          href={item.path}
          className={`block rounded-md px-2 py-1.5 text-sm ${indent} ${
            active
              ? "bg-neutral-900 text-white"
              : "text-neutral-600 hover:bg-neutral-200 hover:text-neutral-900"
          }`}
        >
          {item.label}
        </Link>
      ) : (
        <div
          className={`px-2 pt-3 pb-1 text-xs font-semibold uppercase tracking-wide text-neutral-400 ${indent}`}
        >
          {item.label}
        </div>
      )}
      {item.children?.map((child) => (
        <MenuItem key={child.id} item={child} pathname={pathname} depth={depth + 1} />
      ))}
    </div>
  );
}
