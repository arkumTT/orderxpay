UPDATE integrations SET built = false WHERE provider_key = 'whatsapp_bsp';
ALTER TABLE merchants DROP COLUMN whatsapp_phone_number_id;
