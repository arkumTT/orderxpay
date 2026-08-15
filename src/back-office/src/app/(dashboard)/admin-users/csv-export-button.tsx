"use client";

import type { AdminUser, Role } from "@/lib/types";

function csvCell(v: string | number): string {
  const s = String(v);
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

function toCSV(rows: (string | number)[][]): string {
  return rows.map((r) => r.map(csvCell).join(",")).join("\n");
}

function isoDate(d: Date) {
  return d.toISOString().slice(0, 10);
}

// Client-side export, same approach as the reporting/settlements/disputes/
// risk/KYC pages' exports — the user list is already loaded on the page,
// no new endpoint needed.
export function CsvExportButton({
  users,
}: {
  users: (AdminUser & { roles: Role[] })[];
}) {
  function handleExport() {
    const lines = [
      ["Name", "Email", "Status", "Roles", "Created at"],
      ...users.map((u) => [
        u.name,
        u.email,
        u.status,
        u.roles.map((r) => r.name).join("; "),
        u.created_at,
      ]),
    ];

    const csv = toCSV(lines as (string | number)[][]);
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `orderxpay-admin-users-${isoDate(new Date())}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <button
      type="button"
      onClick={handleExport}
      disabled={users.length === 0}
      className="rounded-md border border-neutral-300 px-3 py-2 text-sm font-medium text-neutral-700 hover:bg-neutral-50 disabled:opacity-50"
    >
      Export CSV
    </button>
  );
}
