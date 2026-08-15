ALTER TABLE payments DROP CONSTRAINT payments_refund_not_exceed_amount;
ALTER TABLE payments DROP COLUMN refunded_amount_pesewas;
DROP TABLE IF EXISTS disputes;
