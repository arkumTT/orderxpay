-- Section 4.11/9.4: fuller Delivery Settings page.
--
-- delivery_enabled is the master "Offer delivery" switch (Prompt 9) — when
-- off, the merchant app hides delivery selection at invoice creation
-- entirely, rather than just leaving an empty list.
ALTER TABLE merchants
  ADD COLUMN delivery_enabled boolean NOT NULL DEFAULT true;

-- flat_fee_pesewas + service_zone back the design's "Flat fee per zone"
-- field on own-delivery contacts (e.g. "GH₵15.00 (Osu / Labone)") — split
-- into a real integer-pesewas amount plus a free-text zone label rather
-- than one combined string, so the amount stays usable in money math.
-- Both nullable: a contact/provider without a flat fee (e.g. "customer
-- arranges" third-party providers) simply doesn't set them.
ALTER TABLE delivery_options
  ADD COLUMN flat_fee_pesewas bigint,
  ADD COLUMN service_zone text;
