-- Replaces the fixed-role admin_users table with a proper RBAC model for
-- the Back Office (Section 7.8): users, roles, permissions, grouped by
-- permission_groups, joined by role_permissions / user_roles, with
-- user_permissions for direct per-user grants beyond a role.
--
-- Scope: this is the Back Office's own auth model. Merchant/staff auth
-- (Section 4.1, 4.9 — the "staff" table) is a separate bounded context and
-- is untouched here.

CREATE TABLE permission_groups (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name        text NOT NULL UNIQUE,
  description text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER permission_groups_set_updated_at BEFORE UPDATE ON permission_groups
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE permissions (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  permission_group_id  uuid NOT NULL REFERENCES permission_groups(id) ON DELETE RESTRICT,
  key                  text NOT NULL UNIQUE, -- e.g. "merchants.manage_status"
  name                 text NOT NULL,
  description          text,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER permissions_set_updated_at BEFORE UPDATE ON permissions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX permissions_permission_group_id_idx ON permissions(permission_group_id);

CREATE TABLE roles (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name        text NOT NULL UNIQUE,
  description text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER roles_set_updated_at BEFORE UPDATE ON roles
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE role_permissions (
  role_id       uuid NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  permission_id uuid NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
  created_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (role_id, permission_id)
);
CREATE INDEX role_permissions_permission_id_idx ON role_permissions(permission_id);

CREATE TABLE users (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name          text NOT NULL,
  email         text NOT NULL UNIQUE,
  password_hash text NOT NULL,
  status        text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended')),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER users_set_updated_at BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE user_roles (
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role_id    uuid NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, role_id)
);
CREATE INDEX user_roles_role_id_idx ON user_roles(role_id);

-- Direct per-user permission grants, on top of whatever their role(s) give
-- them — e.g. a one-off exception without creating a new role.
CREATE TABLE user_permissions (
  user_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  permission_id uuid NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
  created_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, permission_id)
);
CREATE INDEX user_permissions_permission_id_idx ON user_permissions(permission_id);

DROP TABLE IF EXISTS admin_users;

ALTER TABLE audit_log_entries DROP CONSTRAINT audit_log_entries_actor_type_check;
ALTER TABLE audit_log_entries ADD CONSTRAINT audit_log_entries_actor_type_check
  CHECK (actor_type IN ('merchant', 'staff', 'user', 'system'));

-- Seed permission catalog + starter roles, mapped 1:1 to Section 7's
-- module list. Idempotent so re-running migrate-up is safe.

INSERT INTO permission_groups (name, description) VALUES
  ('Merchant Lifecycle', 'Section 7.1'),
  ('Settlements', 'Section 7.2'),
  ('Integrations', 'Section 7.3'),
  ('Pricing', 'Section 7.4'),
  ('Reporting', 'Section 7.5'),
  ('Risk & Fraud', 'Section 7.6'),
  ('Disputes', 'Section 7.7'),
  ('Admin & Access', 'Section 7.8'),
  ('Audit', 'Section 7.9'),
  ('Support', 'Section 7.10')
ON CONFLICT (name) DO NOTHING;

INSERT INTO permissions (permission_group_id, key, name, description)
SELECT g.id, v.key, v.name, v.description
FROM (VALUES
  ('Merchant Lifecycle', 'merchants.view', 'View merchants', 'View merchant list and detail'),
  ('Merchant Lifecycle', 'merchants.manage_status', 'Manage merchant status', 'Suspend/restrict/activate a merchant'),
  ('Merchant Lifecycle', 'merchants.kyc_review', 'Review KYC', 'Approve/reject KYC tier changes'),
  ('Settlements', 'settlements.view', 'View settlements', ''),
  ('Settlements', 'settlements.manage', 'Manage settlements', 'Run/reconcile settlement batches'),
  ('Integrations', 'integrations.manage', 'Manage integrations', ''),
  ('Pricing', 'pricing.view', 'View pricing', ''),
  ('Pricing', 'pricing.manage', 'Manage pricing', 'Set global/merchant fee rules'),
  ('Reporting', 'reporting.view', 'View reporting', ''),
  ('Risk & Fraud', 'risk.view', 'View risk queue', ''),
  ('Risk & Fraud', 'risk.manage', 'Manage risk queue', ''),
  ('Disputes', 'disputes.view', 'View disputes', ''),
  ('Disputes', 'disputes.manage', 'Manage disputes', ''),
  ('Admin & Access', 'admin.manage_users', 'Manage users', 'Create back-office users and assign roles'),
  ('Audit', 'audit.view', 'View audit log', ''),
  ('Support', 'support.view', 'Support console access', '')
) AS v(group_name, key, name, description)
JOIN permission_groups g ON g.name = v.group_name
ON CONFLICT (key) DO NOTHING;

INSERT INTO roles (name, description) VALUES
  ('Super Admin', 'Full access to all back-office functions'),
  ('Compliance Reviewer', 'KYC review and merchant risk/compliance actions'),
  ('Finance', 'Settlement and pricing management'),
  ('Support', 'Read-only merchant lookup and support console access')
ON CONFLICT (name) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r CROSS JOIN permissions p
WHERE r.name = 'Super Admin'
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p
  ON p.key = ANY (ARRAY['merchants.view', 'merchants.kyc_review', 'merchants.manage_status',
                         'risk.view', 'risk.manage', 'disputes.view', 'disputes.manage', 'audit.view'])
WHERE r.name = 'Compliance Reviewer'
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p
  ON p.key = ANY (ARRAY['settlements.view', 'settlements.manage', 'pricing.view',
                         'pricing.manage', 'reporting.view', 'audit.view'])
WHERE r.name = 'Finance'
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p
  ON p.key = ANY (ARRAY['merchants.view', 'support.view', 'audit.view'])
WHERE r.name = 'Support'
ON CONFLICT DO NOTHING;
