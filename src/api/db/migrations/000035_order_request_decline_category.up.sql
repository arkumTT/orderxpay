-- Section 4.6: a structured reason category for declining a customer's
-- order request, alongside the existing free-text decline_reason (which
-- stays as an optional note the merchant can add on top of the category —
-- required on its own only when the category is 'other'). Mirrors
-- disputes.reason_category (000006) — same shape, same idea: a short fixed
-- vocabulary for the common cases plus an escape hatch for everything else.
--
-- Exists so the mobile app can offer a one-tap reason picker instead of a
-- bare text box, and so each category can carry its own canned message when
-- prompting the merchant to let the customer know — see the mobile client
-- for that mapping; nothing server-side depends on the specific wording.
ALTER TABLE order_requests ADD COLUMN decline_reason_category text
  CHECK (decline_reason_category IN (
    'out_of_stock', 'cant_deliver_there', 'not_taking_orders',
    'duplicate', 'suspected_spam', 'other'
  ));
