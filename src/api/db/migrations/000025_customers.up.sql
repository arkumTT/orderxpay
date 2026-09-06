-- A first-class saved-customer list (Section 4.3 order flow revision):
-- until now customer_contact on invoices/order_requests was the only
-- record of a customer anywhere in this system — no persisted name, no
-- way to pick a previous customer without scrolling invoice history.
-- Rows here are upserted automatically whenever a merchant sends an
-- invoice (best-effort, same posture as notification writes — never
-- blocks the actual sale), and can also be added/edited manually from
-- the new Customers page under More.
CREATE TABLE customers (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  name        text,
  contact     text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (merchant_id, contact)
);
CREATE TRIGGER customers_set_updated_at BEFORE UPDATE ON customers
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX customers_merchant_id_idx ON customers(merchant_id);
