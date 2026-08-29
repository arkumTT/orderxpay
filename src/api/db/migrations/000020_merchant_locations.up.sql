-- Merchant pickup/delivery locations (feedback item 4 — "location settings
-- for order pick-up and/or delivery, more than one location for a business
-- with branches"). Deliberately a flat, merchant-managed list for this
-- first cut — no per-delivery-option binding and no lat/lng/map picker yet
-- (see Decisions_Log-equivalent discussion: those are phased follow-ups,
-- not blocking this). A location is a reference point a merchant hands to
-- a third-party provider or tells a customer arranging their own pickup —
-- it's surfaced on the invoice/checkout, not tied to how delivery itself
-- is fulfilled.
CREATE TABLE merchant_locations (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  label       text NOT NULL,
  address     text NOT NULL,
  phone       text,
  is_default  boolean NOT NULL DEFAULT false,
  status      text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX merchant_locations_merchant_id_idx ON merchant_locations (merchant_id);

-- At most one default location per merchant. Partial unique index rather
-- than a boolean-pair check constraint — lets SetDefaultMerchantLocation
-- do "unset old default, set new one" as two statements in a transaction
-- without a transient two-defaults state ever being persisted.
CREATE UNIQUE INDEX merchant_locations_one_default_idx ON merchant_locations (merchant_id) WHERE is_default;

-- Same pattern as invoices.delivery_option_id: nullable reference to the
-- location picked at order time, independent of any delivery_options row.
-- ON DELETE SET NULL — deactivating/deleting a location shouldn't corrupt
-- historical invoices, it just stops showing a resolved pickup address.
ALTER TABLE invoices ADD COLUMN pickup_location_id uuid REFERENCES merchant_locations(id) ON DELETE SET NULL;
