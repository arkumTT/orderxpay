-- Optional customer-supplied name on order requests (hosted catalog page,
-- Section 4.6). Customers today are identified to the merchant only by
-- customer_contact (a phone number) — there's no customers table in this
-- system. Nullable/optional on purpose: the WhatsApp/SMS-based ordering
-- flow this platform is built around works fine on a phone number alone,
-- and requiring a name would add friction for customers who don't bother
-- typing one. When present, it's just a nicer label for the merchant
-- (mobile app's order requests list currently has nothing better than the
-- phone number itself to show).
ALTER TABLE order_requests ADD COLUMN customer_name text;
