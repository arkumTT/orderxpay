import { listAdminUsersWithRoles, listRoles } from "@/lib/users";
import { ApiError } from "@/lib/session";
import { CreateUserForm } from "./create-user-form";
import { UserRow } from "./user-row";
import { CsvExportButton } from "./csv-export-button";

export default async function AdminUsersPage() {
  let users, roles;
  try {
    [users, roles] = await Promise.all([
      listAdminUsersWithRoles(),
      listRoles(),
    ]);
  } catch (err) {
    if (err instanceof ApiError && err.status === 403) {
      return (
        <p className="text-sm text-neutral-500">
          You don&apos;t have permission to manage Back Office users
          (requires admin.manage_users).
        </p>
      );
    }
    throw err;
  }

  return (
    <div className="space-y-6">
      <div>
        <div className="flex items-baseline gap-2">
          <h1 className="text-2xl font-semibold text-neutral-900">
            Admin Users, Roles &amp; Permissions
          </h1>
          <span className="text-xs font-mono text-neutral-400">
            Section 7.8
          </span>
        </div>
        <p className="text-sm text-neutral-500">
          Role-based access for the Back Office team itself — each user is
          scoped to only the data and actions their roles grant.
        </p>
      </div>

      <div className="flex flex-wrap items-start justify-between gap-3">
        <CreateUserForm />
        <CsvExportButton users={users} />
      </div>

      <div>
        <h2 className="mb-2 text-sm font-semibold text-neutral-700">
          Users ({users.length})
        </h2>
        <div className="overflow-x-auto rounded-lg border border-neutral-200">
          <table className="w-full text-sm">
            <thead className="bg-neutral-50 text-left text-xs uppercase tracking-wide text-neutral-500">
              <tr>
                <th className="px-4 py-2">User</th>
                <th className="px-4 py-2">Roles</th>
                <th className="px-4 py-2">Status</th>
                <th className="px-4 py-2">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-neutral-100">
              {users.map((u) => (
                <UserRow key={u.id} user={u} allRoles={roles} />
              ))}
            </tbody>
          </table>
        </div>
      </div>

      <div>
        <h2 className="mb-2 text-sm font-semibold text-neutral-700">
          Roles &amp; what they grant
        </h2>
        <div className="grid gap-3 sm:grid-cols-2">
          {roles.map((r) => (
            <div
              key={r.id}
              className="rounded-lg border border-neutral-200 p-3"
            >
              <div className="font-medium text-neutral-900">{r.name}</div>
              {r.description && (
                <div className="text-xs text-neutral-500">
                  {r.description}
                </div>
              )}
              <div className="mt-2 flex flex-wrap gap-1">
                {r.permissions.map((p) => (
                  <span
                    key={p.id}
                    className="rounded-full bg-neutral-100 px-2 py-0.5 text-xs text-neutral-600"
                    title={p.description ?? undefined}
                  >
                    {p.key}
                  </span>
                ))}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
