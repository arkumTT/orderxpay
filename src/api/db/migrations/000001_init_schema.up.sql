-- Core data model per OrderxPay_Product_Architecture_Framework.html, Section 10.
-- All monetary values are bigint pesewas (GHS lowest unit) — never floats.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Section 7.8: back-office staff, distinct from merchant-side "staff" (Section 4.9)
CREATE TABLE admin_users (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name          text NOT NULL,
  email         text NOT NULL UNIQUE,
  password_hash text NOT NULL,
  role          text NOT NULL CHECK (role IN ('super_admin', 'compliance', 'finance', 'support')),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER admin_users_set_updated_at BEFORE UPDATE ON admin_users
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE merchants (
  id                         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_name              text NOT NULL,
  category                   text,
  phone                      text NOT NULL UNIQUE,
  kyc_tier                   smallint NOT NULL DEFAULT 0 CHECK (kyc_tier IN (0, 1)),
  status                     text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'restricted', 'suspended')),
  service_charge_allocation  text NOT NULL DEFAULT 'customer_only' CHECK (service_charge_allocation IN ('customer_only', 'merchant_only', 'split')),
  service_charge_split_bps   int,
  payout_account_type        text CHECK (payout_account_type IN ('momo', 'bank')),
  payout_account_ref         text,
  payout_schedule            text NOT NULL DEFAULT 'on_demand' CHECK (payout_schedule IN ('on_demand', 'scheduled')),
  payout_min_threshold_pesewas bigint NOT NULL DEFAULT 0,
  created_at                 timestamptz NOT NULL DEFAULT now(),
  updated_at                 timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER merchants_set_updated_at BEFORE UPDATE ON merchants
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Section 4.9: merchant-side multi-user staff
CREATE TABLE staff (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  name        text NOT NULL,
  phone       text NOT NULL UNIQUE,
  role        text NOT NULL DEFAULT 'staff' CHECK (role IN ('owner', 'staff')),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER staff_set_updated_at BEFORE UPDATE ON staff
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX staff_merchant_id_idx ON staff(merchant_id);

CREATE TABLE items (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id         uuid NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  name                text NOT NULL,
  unit_price_pesewas  bigint NOT NULL CHECK (unit_price_pesewas >= 0),
  qty_unit            text,
  image_url           text,
  availability_status text NOT NULL DEFAULT 'in_stock' CHECK (availability_status IN ('in_stock', 'out_of_stock', 'made_to_order')),
  archived_at         timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER items_set_updated_at BEFORE UPDATE ON items
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX items_merchant_id_idx ON items(merchant_id);

-- Section 4.6: customer-initiated request, pre-invoice
CREATE TABLE order_requests (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id      uuid NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  customer_contact text NOT NULL,
  requested_items  jsonb NOT NULL,
  status           text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'declined')),
  decline_reason   text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER order_requests_set_updated_at BEFORE UPDATE ON order_requests
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX order_requests_merchant_id_idx ON order_requests(merchant_id);

-- Section 4.11: merchant's configured delivery choices
CREATE TABLE delivery_options (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id         uuid NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  type                text NOT NULL CHECK (type IN ('own_contact', 'verified_provider')),
  contact_name        text,
  contact_phone       text,
  provider_key        text,
  deep_link_template  text,
  fee_handling_default text NOT NULL DEFAULT 'external' CHECK (fee_handling_default IN ('bundled', 'external')),
  status              text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER delivery_options_set_updated_at BEFORE UPDATE ON delivery_options
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX delivery_options_merchant_id_idx ON delivery_options(merchant_id);

-- Section 4.3, 4.11: central payable object
CREATE TABLE invoices (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id            uuid NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  order_request_id       uuid REFERENCES order_requests(id) ON DELETE SET NULL,
  reference              text NOT NULL UNIQUE,
  customer_contact       text NOT NULL,
  subtotal_pesewas       bigint NOT NULL CHECK (subtotal_pesewas >= 0),
  service_charge_pesewas bigint NOT NULL DEFAULT 0 CHECK (service_charge_pesewas >= 0),
  service_charge_allocation text NOT NULL CHECK (service_charge_allocation IN ('customer_only', 'merchant_only', 'split')),
  total_pesewas          bigint NOT NULL CHECK (total_pesewas >= 0),
  status                 text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'sent', 'viewed', 'partially_paid', 'paid', 'expired', 'cancelled', 'refunded')),
  delivery_option_id     uuid REFERENCES delivery_options(id) ON DELETE SET NULL,
  delivery_address       text,
  delivery_fee_handling  text CHECK (delivery_fee_handling IN ('bundled', 'external')),
  delivery_fee_pesewas   bigint,
  expires_at             timestamptz,
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER invoices_set_updated_at BEFORE UPDATE ON invoices
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX invoices_merchant_id_idx ON invoices(merchant_id);
CREATE INDEX invoices_status_idx ON invoices(status);

CREATE TABLE invoice_line_items (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id         uuid NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
  item_id            uuid REFERENCES items(id) ON DELETE SET NULL,
  description        text NOT NULL,
  unit_price_pesewas bigint NOT NULL CHECK (unit_price_pesewas >= 0),
  quantity           int NOT NULL CHECK (quantity > 0),
  line_total_pesewas bigint NOT NULL CHECK (line_total_pesewas >= 0)
);
CREATE INDEX invoice_line_items_invoice_id_idx ON invoice_line_items(invoice_id);

-- Section 4.5: one invoice can have multiple partial payments
CREATE TABLE payments (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id     uuid NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
  psp_reference  text NOT NULL,
  method         text NOT NULL CHECK (method IN ('momo', 'card', 'ussd')),
  amount_pesewas bigint NOT NULL CHECK (amount_pesewas > 0),
  status         text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'success', 'failed')),
  paid_at        timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX payments_psp_reference_uidx ON payments(psp_reference);
CREATE INDEX payments_invoice_id_idx ON payments(invoice_id);

-- Section 7.2: reconciliation / payout ledger
CREATE TABLE settlements (
  id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id               uuid NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  period_start              date NOT NULL,
  period_end                date NOT NULL,
  gross_collections_pesewas bigint NOT NULL DEFAULT 0,
  psp_fees_pesewas          bigint NOT NULL DEFAULT 0,
  commission_pesewas        bigint NOT NULL DEFAULT 0,
  net_payout_pesewas        bigint NOT NULL DEFAULT 0,
  status                    text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'paid', 'failed')),
  created_at                timestamptz NOT NULL DEFAULT now(),
  updated_at                timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER settlements_set_updated_at BEFORE UPDATE ON settlements
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX settlements_merchant_id_idx ON settlements(merchant_id);

-- Section 6.4: transactional vs marketing messages, with consent
CREATE TABLE conversations (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id      uuid NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  customer_contact text NOT NULL,
  channel          text NOT NULL CHECK (channel IN ('whatsapp', 'sms', 'email')),
  direction        text NOT NULL CHECK (direction IN ('inbound', 'outbound')),
  message_type     text NOT NULL CHECK (message_type IN ('transactional', 'marketing')),
  template_id      text,
  consent          boolean NOT NULL DEFAULT false,
  created_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX conversations_merchant_id_idx ON conversations(merchant_id);

-- Section 7.4: pricing config, merchant_id null = global default
CREATE TABLE fee_rules (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id     uuid REFERENCES merchants(id) ON DELETE CASCADE,
  commission_bps  int NOT NULL CHECK (commission_bps >= 0),
  allocation_type text NOT NULL CHECK (allocation_type IN ('customer_only', 'merchant_only', 'split')),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER fee_rules_set_updated_at BEFORE UPDATE ON fee_rules
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE UNIQUE INDEX fee_rules_global_default_uidx ON fee_rules((1)) WHERE merchant_id IS NULL;
CREATE UNIQUE INDEX fee_rules_merchant_id_uidx ON fee_rules(merchant_id) WHERE merchant_id IS NOT NULL;

-- Section 7.9: immutable audit trail, both merchant-app and back-office actions
CREATE TABLE audit_log_entries (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id      uuid NOT NULL,
  actor_type    text NOT NULL CHECK (actor_type IN ('merchant', 'staff', 'admin_user', 'system')),
  action        text NOT NULL,
  target_entity text NOT NULL,
  target_id     uuid,
  before_state  jsonb,
  after_state   jsonb,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX audit_log_entries_target_idx ON audit_log_entries(target_entity, target_id);
