-- Feedback item 4 follow-up: "Use current location" on the Add/Edit
-- Location sheet captures device GPS and reverse-geocodes it into the
-- address text — these columns keep the actual coordinates too (not just
-- the human-readable address), so a later feature (handing a precise pin
-- to a third-party provider deep link, e.g. Bolt's pickup= param) has real
-- data to work with instead of needing to re-geocode the address text.
-- Nullable — a location entered by hand (no GPS capture) simply has none.
ALTER TABLE merchant_locations ADD COLUMN lat double precision;
ALTER TABLE merchant_locations ADD COLUMN lng double precision;
