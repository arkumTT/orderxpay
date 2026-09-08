-- Section 4.1/7.1: forks verification by business type, and gives the tiers
-- something to actually enforce.
--
-- Until now kyc_tier was 0|1, set on approval, and read by nothing — no code
-- path anywhere allowed or denied on it. This makes the tier a control:
--
--   Tier 0  unverified
--   Tier 1  informal trader — Ghana Card number + liveness selfie
--   Tier 2  registered business — Tier 1 evidence plus TIN, registration
--           number, entity type, and a registration certificate
--
-- The Ghana Card is deliberately still number-plus-liveness only: no image
-- of the card is captured or stored anywhere, in line with the restriction
-- on copying/scanning Ghana Card IDs. That restriction is specific to the
-- card — a business registration certificate is an ordinary commercial
-- document, so registration_cert_path stores one the same way
-- selfie_photo_path does (private dir, permission-gated read endpoint).

ALTER TABLE merchants DROP CONSTRAINT merchants_kyc_tier_check;
ALTER TABLE merchants ADD CONSTRAINT merchants_kyc_tier_check CHECK (kyc_tier IN (0, 1, 2));

-- NULL until a submission is approved: an unverified merchant has not yet
-- told us which kind of business they are, and guessing would be wrong.
ALTER TABLE merchants ADD COLUMN business_type text
  CHECK (business_type IN ('informal', 'registered'));

ALTER TABLE kyc_submissions ADD COLUMN business_type text NOT NULL DEFAULT 'informal'
  CHECK (business_type IN ('informal', 'registered'));
ALTER TABLE kyc_submissions ALTER COLUMN business_type DROP DEFAULT;
ALTER TABLE kyc_submissions ADD COLUMN tin text;
ALTER TABLE kyc_submissions ADD COLUMN entity_type text
  CHECK (entity_type IN ('sole_proprietorship', 'partnership', 'company_limited_by_shares', 'company_limited_by_guarantee', 'ngo'));
ALTER TABLE kyc_submissions ADD COLUMN registration_cert_path text;

-- The fork itself, enforced in the schema rather than only at the handler:
-- a registered submission is not a registered submission without its
-- registration evidence.
ALTER TABLE kyc_submissions ADD CONSTRAINT kyc_submissions_registered_evidence CHECK (
  business_type = 'informal' OR (
    business_reg_number IS NOT NULL AND business_reg_number <> ''
    AND tin IS NOT NULL AND tin <> ''
    AND entity_type IS NOT NULL
    AND registration_cert_path IS NOT NULL AND registration_cert_path <> ''
  )
);

-- Each path leads to exactly one tier, so the tier can never disagree with
-- the evidence that was actually reviewed.
ALTER TABLE kyc_submissions DROP CONSTRAINT kyc_submissions_requested_tier_check;
ALTER TABLE kyc_submissions ADD CONSTRAINT kyc_submissions_requested_tier_check CHECK (
  (business_type = 'informal' AND requested_tier = 1)
  OR (business_type = 'registered' AND requested_tier = 2)
);

-- Volume caps per tier. Every column is NULLABLE and every row ships NULL,
-- meaning "no cap" — the enforcement code no-ops on an unset limit.
--
-- These are deliberately NOT pre-filled. Tier thresholds for this kind of
-- account are set by Bank of Ghana guidance, and inventing figures that
-- look researched is worse than shipping none: the mechanism works the
-- moment real numbers are entered in Back Office. Confirm against current
-- official BoG guidance before setting any value here.
--
-- Ghana is UTC+0 year-round, so the daily window is plain UTC calendar day.
CREATE TABLE kyc_tier_limits (
  tier                    smallint PRIMARY KEY CHECK (tier IN (0, 1, 2)),
  per_transaction_pesewas bigint CHECK (per_transaction_pesewas IS NULL OR per_transaction_pesewas > 0),
  daily_pesewas           bigint CHECK (daily_pesewas IS NULL OR daily_pesewas > 0),
  cumulative_pesewas      bigint CHECK (cumulative_pesewas IS NULL OR cumulative_pesewas > 0),
  updated_at              timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER kyc_tier_limits_set_updated_at BEFORE UPDATE ON kyc_tier_limits
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

INSERT INTO kyc_tier_limits (tier) VALUES (0), (1), (2);
