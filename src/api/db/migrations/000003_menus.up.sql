-- Back Office navigation menus (Section 13: "Admin shell/navigation"),
-- driven by the RBAC permission catalog from 000002 rather than hardcoded
-- in the frontend. A menu with permission_id NULL is visible to any
-- authenticated Back Office user; otherwise it's only visible to users
-- whose effective permissions (via role or direct grant) include it.
-- Submenus are just rows whose parent_id points at another menu row.

CREATE TABLE menus (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_id     uuid REFERENCES menus(id) ON DELETE CASCADE,
  permission_id uuid REFERENCES permissions(id) ON DELETE SET NULL,
  label         text NOT NULL,
  path          text,
  icon          text,
  sort_order    int NOT NULL DEFAULT 0,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER menus_set_updated_at BEFORE UPDATE ON menus
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX menus_parent_id_idx ON menus(parent_id);
CREATE INDEX menus_permission_id_idx ON menus(permission_id);

-- New permission for managing the menu catalog itself, distinct from
-- admin.manage_users (managing who has access vs. managing what the nav
-- shows).
INSERT INTO permissions (permission_group_id, key, name, description)
SELECT g.id, 'admin.manage_menus', 'Manage navigation menus', 'Create/edit/reorder Back Office sidebar menus'
FROM permission_groups g WHERE g.name = 'Admin & Access'
ON CONFLICT (key) DO NOTHING;

-- Re-grant Super Admin every permission, including the one just added —
-- run this at the end of any migration that introduces new permissions.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r CROSS JOIN permissions p WHERE r.name = 'Super Admin'
ON CONFLICT DO NOTHING;

-- Seed the menu tree to match the Back Office's current route structure
-- (src/back-office/src/lib/nav.ts), grouped into two real parent/submenu
-- pairs (Merchants, Admin & Access) plus flat top-level items.

INSERT INTO menus (parent_id, permission_id, label, path, sort_order) VALUES
  (NULL, NULL, 'Overview', '/', 0);

WITH parent AS (
  INSERT INTO menus (parent_id, permission_id, label, path, sort_order)
  SELECT NULL, p.id, 'Merchants', NULL, 10 FROM permissions p WHERE p.key = 'merchants.view'
  RETURNING id
)
INSERT INTO menus (parent_id, permission_id, label, path, sort_order)
SELECT parent.id, p.id, v.label, v.path, v.sort_order
FROM parent
CROSS JOIN (VALUES
  ('merchants.view', 'All Merchants', '/merchants', 0),
  ('merchants.kyc_review', 'KYC Review', '/merchants/kyc-review', 1)
) AS v(perm_key, label, path, sort_order)
JOIN permissions p ON p.key = v.perm_key;

INSERT INTO menus (parent_id, permission_id, label, path, sort_order)
SELECT NULL, p.id, v.label, v.path, v.sort_order
FROM (VALUES
  ('settlements.view', 'Settlements', '/settlements', 20),
  ('pricing.view', 'Pricing', '/pricing', 30),
  ('integrations.manage', 'Integrations', '/integrations', 40),
  ('reporting.view', 'Reporting', '/reporting', 50),
  ('risk.view', 'Risk & Fraud', '/risk', 60),
  ('disputes.view', 'Disputes', '/disputes', 70)
) AS v(perm_key, label, path, sort_order)
JOIN permissions p ON p.key = v.perm_key;

WITH parent AS (
  INSERT INTO menus (parent_id, permission_id, label, path, sort_order)
  SELECT NULL, p.id, 'Admin & Access', NULL, 80 FROM permissions p WHERE p.key = 'admin.manage_users'
  RETURNING id
)
INSERT INTO menus (parent_id, permission_id, label, path, sort_order)
SELECT parent.id, p.id, v.label, v.path, v.sort_order
FROM parent
CROSS JOIN (VALUES
  ('admin.manage_users', 'Users', '/admin-users', 0),
  ('audit.view', 'Audit Log', '/audit-log', 1)
) AS v(perm_key, label, path, sort_order)
JOIN permissions p ON p.key = v.perm_key;

INSERT INTO menus (parent_id, permission_id, label, path, sort_order)
SELECT NULL, p.id, 'Support', '/support', 90
FROM permissions p WHERE p.key = 'support.view';
