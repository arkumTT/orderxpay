DELETE FROM feature_flags WHERE key = 'hubtel_ussd_fallback';
ALTER TABLE payments DROP COLUMN provider;
