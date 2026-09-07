-- Section 4.1/7.1: adds the liveness-check selfie captured during Tier 1
-- verification. Stores only an opaque UUID+ext filename (e.g.
-- "3f1c...-a1b2.jpg"), never a full path or public URL — the file itself
-- lives under KYCUploadDir/{merchant_id}/, a directory deliberately kept
-- outside the app.Static("/uploads", ...) mount used for catalog item
-- photos, because this is someone's face tied to a real identity document.
-- Serving it back out goes through GetKYCSelfiePhoto, gated by the same
-- merchants.kyc_review permission as the review queue itself — never a
-- direct static file mount.
ALTER TABLE kyc_submissions ADD COLUMN selfie_photo_path text;
