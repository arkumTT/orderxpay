import "server-only";
import { apiFetchServer } from "./session";

// Mirrors MenuNode in src/api/internal/http/handlers/menus.go.
export type MenuNode = {
  id: string;
  label: string;
  path?: string;
  icon?: string;
  sort_order: number;
  children?: MenuNode[];
};

export function getMyMenus(): Promise<MenuNode[]> {
  return apiFetchServer<MenuNode[]>("/api/v1/admin/menus/me");
}

/** Flattens the tree (parents + children) for simple grid/list displays. */
export function flattenMenus(nodes: MenuNode[]): MenuNode[] {
  return nodes.flatMap((n) => [n, ...(n.children ? flattenMenus(n.children) : [])]);
}
