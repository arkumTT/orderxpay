-- Lossy in one direction: any merchant already promoted to Tier 2 is folded
-- back to Tier 1, since the pre-fork schema has no way to express "verified
-- registered business". Their submission evidence survives in the dropped
-- columns' absence only as the reviewer's notes, so re-running the up
-- migration does not restore the tier — a reviewer re-approves.
DROP TABLE kyc_tier_limits;

ALTER TABLE kyc_submissions DROP CONSTRAINT kyc_submissions_requested_tier_check;
ALTER TABLE kyc_submissions DROP CONSTRAINT kyc_submissions_registered_evidence;
ALTER TABLE kyc_submissions DROP COLUMN registration_cert_path;
ALTER TABLE kyc_submissions DROP COLUMN entity_type;
ALTER TABLE kyc_submissions DROP COLUMN tin;
ALTER TABLE kyc_submissions DROP COLUMN business_type;

DELETE FROM kyc_submissions WHERE requested_tier <> 1;
ALTER TABLE kyc_submissions ADD CONSTRAINT kyc_submissions_requested_tier_check CHECK (requested_tier = 1);

ALTER TABLE merchants DROP COLUMN business_type;
UPDATE merchants SET kyc_tier = 1 WHERE kyc_tier > 1;
ALTER TABLE merchants DROP CONSTRAINT merchants_kyc_tier_check;
ALTER TABLE merchants ADD CONSTRAINT merchants_kyc_tier_check CHECK (kyc_tier IN (0, 1));
