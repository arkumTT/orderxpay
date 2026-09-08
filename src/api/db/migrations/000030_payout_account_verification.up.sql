-- Section 4.1/7.2: turns payout_account_type/payout_account_ref from
-- collected-nowhere schema into a real, PSP-verified destination.
--
-- payout_account_ref already holds the account number (bank) or wallet
-- number (mobile money). This adds what's needed to actually verify it:
--
--   payout_bank_code            the network/bank code Paystack's /bank
--                                endpoint returns (e.g. "MTN", "058") —
--                                required by both /bank/resolve now and the
--                                Transfer API later, so it's captured once.
--   payout_account_name         the account holder's name AS RESOLVED BY
--                                PAYSTACK from the account number — never
--                                merchant-supplied text. This is the
--                                name-match: a wrong digit in the account
--                                number resolves to a stranger's name,
--                                which the merchant is shown and asked to
--                                confirm before anything is saved, catching
--                                the single most common blocked-funds
--                                failure before it costs anyone money.
--   payout_account_verified_at  null until a resolve+confirm succeeds.
--
-- Changing any of type/ref/bank_code must clear name+verified_at in the
-- same request (enforced in the handler, not a trigger) — a resolve
-- against account A must never be presented as verification of account B.
ALTER TABLE merchants ADD COLUMN payout_bank_code text;
ALTER TABLE merchants ADD COLUMN payout_account_name text;
ALTER TABLE merchants ADD COLUMN payout_account_verified_at timestamptz;
