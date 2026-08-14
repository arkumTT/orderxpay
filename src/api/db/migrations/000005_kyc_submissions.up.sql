-- Section 4.1/7.1: a Tier 1 upgrade request, reviewed by Back Office staff.
-- Text-only for now (Ghana Card number, business registration number,
-- freeform notes) rather than photo/selfie capture — that needs a file
-- storage vendor decision (Section 4.1's "Ghana Card capture + selfie
-- liveness check") not yet made, tracked as follow-up. This still lets a
-- reviewer make a real decision instead of the queue being empty forever.
CREATE TABLE kyc_submissions (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id          uuid NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  requested_tier       smallint NOT NULL CHECK (requested_tier = 1),
  ghana_card_number    text NOT NULL,
  business_reg_number  text,
  notes                text,
  status               text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'more_info_requested')),
  reviewer_notes       text,
  reviewed_by          uuid REFERENCES users(id) ON DELETE SET NULL,
  reviewed_at          timestamptz,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER kyc_submissions_set_updated_at BEFORE UPDATE ON kyc_submissions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX kyc_submissions_merchant_id_idx ON kyc_submissions(merchant_id);
CREATE INDEX kyc_submissions_status_idx ON kyc_submissions(status);

-- At most one open submission per merchant at a time — resubmitting after
-- more_info_requested happens by updating the existing row, not creating a
-- second one; approved/rejected are terminal and free up a new submission.
CREATE UNIQUE INDEX kyc_submissions_one_open_per_merchant
  ON kyc_submissions(merchant_id)
  WHERE status IN ('pending', 'more_info_requested');
