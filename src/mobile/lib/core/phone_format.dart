/// Ghana phone normalization shared by registration (OnboardingScreen) and
/// login (ApiClient) — both need to turn whatever a merchant typed into
/// the same E.164 string CreateMerchant stores, or a phone that worked at
/// signup won't match at login.
///
/// The assumption: what's typed is a local 9-digit number with no leading
/// 0 and no country code (the registration field's own hint text, "20 553
/// 7712", is what teaches a merchant that format) — whitespace is
/// stripped and +233 prepended. Input that's already +233-qualified is
/// left untouched, so a value round-tripped from a previous normalization
/// doesn't get double-prefixed.
String normalizeGhPhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'\s'), '');
  if (digits.startsWith('+233')) return digits;
  return '+233$digits';
}
