-- Section 7's roadmap item "Paystack subaccounts and split payments" — the
-- architectural piece flagged in the fee-architecture brief as needing
-- counsel's confirmation before scaling, because it changes who custodies
-- merchant funds: today every cedi lands in OrderxPay's own Paystack
-- balance and leaves by a manual payout (settlements table); split
-- payments make Paystack pay the merchant's share directly to their own
-- bank/momo at charge time, bypassing OrderxPay's balance entirely.
--
-- This migration only adds the plumbing. It changes no behavior by itself:
--   merchants.paystack_subaccount_code  set once a subaccount is
--                                        provisioned (SetPayoutAccount
--                                        creates/updates one automatically
--                                        whenever a payout account is
--                                        verified — inert until a payment
--                                        actually asks for it).
--   payments.paystack_subaccount_code   set per PAYMENT, only when that
--                                        specific charge was actually split
--                                        — a merchant switched to split
--                                        mid-stream keeps their pre-switch
--                                        payments on the ordinary manual-
--                                        settlement path, which is why this
--                                        lives on payments, not merchants.
--
-- The feature flag below gates the only thing that actually moves money
-- differently: whether InitiateCheckoutPayment passes `subaccount` to
-- Paystack at all. It ships enabled_globally = false and with no merchants
-- opted in, so nothing about how money moves changes until it's
-- deliberately turned on — the default this migration's own INSERT
-- inherits from feature_flags' schema default.
ALTER TABLE merchants ADD COLUMN paystack_subaccount_code text;
ALTER TABLE payments ADD COLUMN paystack_subaccount_code text;

INSERT INTO feature_flags (key, name, description) VALUES
  ('paystack_split_payments', 'Paystack Split Payments',
   'Splits a payment at charge time so the merchant''s share settles to their own Paystack subaccount directly, instead of through OrderxPay''s balance and a manual settlement. Requires the merchant to have a verified payout account (subaccount is provisioned automatically when one is set). Confirm the regulatory posture (see the fee-architecture brief) before enabling broadly.');
