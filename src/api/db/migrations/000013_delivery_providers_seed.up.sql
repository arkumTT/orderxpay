-- Section 9.4: product decision (2026-08-16) to treat Uber Connect and
-- Yango as available in Ghana alongside Bolt Send, superseding the
-- "unconfirmed" caution the original seed (migration 000009) recorded for
-- both. Deep-link parameter names are illustrative, same as Bolt's own
-- entry — verify against each provider's current API before going live.
INSERT INTO delivery_providers (key, name, deep_link_template, notes) VALUES
  ('uber_connect', 'Uber Connect', 'https://m.uber.com/ul/?action=setPickup&pickup={pickup}&dropoff={dropoff}', 'Added 2026-08-16 as available in Ghana alongside Bolt Send — deep-link parameter names are illustrative, verify against Uber''s current API before going live.'),
  ('yango', 'Yango', 'https://yango.go.link/route?start={pickup}&end={dropoff}', 'Added 2026-08-16 as available in Ghana alongside Bolt Send — deep-link parameter names are illustrative, verify against Yango''s current API before going live.');
