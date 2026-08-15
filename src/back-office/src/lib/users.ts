import "server-only";
import { apiFetchServer } from "./session";
import type { AdminUser, Role } from "./types";

export function listAdminUsers(): Promise<AdminUser[]> {
  return apiFetchServer<AdminUser[]>("/api/v1/admin/users");
}

export function listUserRoles(userId: string): Promise<Role[]> {
  return apiFetchServer<Role[]>(`/api/v1/admin/users/${userId}/roles`);
}

export function listRoles(): Promise<Role[]> {
  return apiFetchServer<Role[]>("/api/v1/admin/roles");
}

export async function listAdminUsersWithRoles(): Promise<
  (AdminUser & { roles: Role[] })[]
> {
  const users = await listAdminUsers();
  const roles = await Promise.all(users.map((u) => listUserRoles(u.id)));
  return users.map((u, i) => ({ ...u, roles: roles[i] }));
}
