/// Ghana phone normalization shared by registration (OnboardingScreen) and
/// login (ApiClient) — both must turn whatever a merchant typed into the
/// same E.164 string CreateMerchant stores, or a phone that worked at
/// signup won't match at login.
///
/// Handles the forms a Ghanaian merchant actually types:
///   592824972        bare 9-digit local (what the field hint shows)
///   0592824972       with the trunk 0 — how most people write their number
///   +233592824972    already E.164
///   233592824972     country code without the +
///   059 282 4972     any of the above with spaces / dashes / parens
/// All normalize to `+233592824972`. Digits-only input that's already a
/// bare local is left as-is aside from the +233 prefix.
///
/// The trunk-0 case is the one that bit a real merchant: before this
/// stripped it, someone entering their number the normal way got
/// `+2330592824972` stored, which then never matched at phone login.
String normalizeGhPhone(String raw) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');

  // Peel an explicit country code — "+233…" or "233…" — but only when the
  // length confirms it's really a country code and not a local number that
  // happens to start 233 (Glo's 023-3xx-xxxx range): 233 + 9-digit local,
  // optionally plus the stray trunk 0.
  if (digits.startsWith('233') && (digits.length == 12 || digits.length == 13)) {
    digits = digits.substring(3);
  }

  // A local Ghanaian mobile number is 9 digits. People habitually write it
  // with the trunk 0 ("024 123 4567") — that 0 isn't part of the E.164
  // form and must come off, or the stored number never matches at login.
  if (digits.length == 10 && digits.startsWith('0')) {
    digits = digits.substring(1);
  }

  return '+233$digits';
}
