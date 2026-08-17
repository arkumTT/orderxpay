ALTER TABLE delivery_options
  DROP COLUMN flat_fee_pesewas,
  DROP COLUMN service_zone;

ALTER TABLE merchants
  DROP COLUMN delivery_enabled;
