/// OrderxPay is Ghana-only for now — merchants don't have a country field
/// in the data model, so this mirrors the fixed "🇬🇭 +233" prefix already
/// hardcoded in the onboarding screen and (on the web side) the hosted
/// catalog page, rather than inventing a per-merchant lookup that doesn't
/// exist. Revisit if multi-country ever ships.
const String kCountryCode = '+233';
const String kCountryFlag = '🇬🇭';

/// Turns whatever a merchant typed, or a phone yanked from the device's
/// contact book, into the clean local-number digits the phone field
/// should display: strips everything but digits, then drops a leading
/// country code (233) or trunk zero (0) if present, so a number handed to
/// us as "+233 24 111 2222", "0241112222", or "24 111 2222" all end up
/// showing as "241112222".
String localDigitsFrom(String raw) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('233')) {
    digits = digits.substring(3);
  } else if (digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  return digits;
}

/// Joins the fixed country code with a local-number field's raw text into
/// a clean E.164 contact string for the API — strips spaces/punctuation
/// first so what gets sent is always just "+233" followed by digits,
/// regardless of how the merchant grouped them on screen.
String toE164(String localNumberInput) {
  final digits = localNumberInput.replaceAll(RegExp(r'\D'), '');
  return '$kCountryCode$digits';
}
