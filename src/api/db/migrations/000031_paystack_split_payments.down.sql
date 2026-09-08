DELETE FROM feature_flags WHERE key = 'paystack_split_payments';
ALTER TABLE payments DROP COLUMN paystack_subaccount_code;
ALTER TABLE merchants DROP COLUMN paystack_subaccount_code;
