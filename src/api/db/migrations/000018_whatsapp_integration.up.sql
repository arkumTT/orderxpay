-- Section 4.4/6.2/7.3: real WhatsApp Cloud API integration (direct Meta,
-- no BSP middleman — see Decisions Log). Each merchant gets their own
-- phone number registered under the platform's single WhatsApp Business
-- Account (WABA). Meta's access token is account-level and works across
-- every number under that WABA, so which merchant an inbound webhook
-- belongs to is resolved by matching the receiving phone_number_id against
-- this column — not by any per-merchant credential.
ALTER TABLE merchants ADD COLUMN whatsapp_phone_number_id text UNIQUE;

-- Real code now reads this integration's secret (see internal/whatsapp) —
-- flip the flag SetIntegrationSecret checks before it'll accept a value.
UPDATE integrations SET built = true WHERE provider_key = 'whatsapp_bsp';
