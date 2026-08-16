-- Section 4.4/6.2 merchant-side WhatsApp auto-reply settings. Real, persisted
-- merchant preferences — same posture as payout_fee_absorption (migration
-- 000011): stored and editable now even though the WhatsApp Business
-- Solution Provider integration itself (Section 7.3, integrations.provider_key
-- = 'whatsapp_bsp', built = false) doesn't exist yet, so nothing actually
-- fires on these settings until that connection is built.
--
-- whatsapp_greeting_message is nullable: null means the merchant hasn't
-- customized it, and the app composes a default from the merchant's own
-- business name + catalog link rather than storing a duplicate copy that
-- would go stale if the business name changes.
ALTER TABLE merchants
  ADD COLUMN whatsapp_auto_reply_enabled boolean NOT NULL DEFAULT true,
  ADD COLUMN whatsapp_greeting_message text;
