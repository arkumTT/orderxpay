import 'package:flutter_test/flutter_test.dart';
import 'package:orderxpay_mobile/core/phone_format.dart';

/// Shared by OnboardingScreen (signup) and ApiClient.login (login) — the
/// point of this test is that every way a merchant might write the same
/// number produces the exact same string, since that string is what has
/// to match between CreateMerchant's stored phone and MerchantLogin's
/// lookup.
void main() {
  const canonical = '+233592824972';

  test('every common way of typing one number normalizes identically', () {
    for (final input in [
      '592824972', // bare 9-digit local — what the field hint shows
      '0592824972', // with the trunk 0 — how most people write it
      '+233592824972', // already E.164
      '233592824972', // country code, no +
      '059 282 4972', // trunk 0 with spaces
      '59 282 4972', // bare local with spaces
      '+233 59 282 4972', // E.164 with spaces
      '(059) 282-4972', // punctuation
    ]) {
      expect(normalizeGhPhone(input), canonical, reason: 'input: "$input"');
    }
  });

  test('drops the trunk 0 from a 10-digit local number', () {
    // The exact bug: a real merchant typed 0592824972 and got
    // +2330592824972 stored, which never matched at login.
    expect(normalizeGhPhone('0592824972'), '+233592824972');
    expect(normalizeGhPhone('0248123456'), '+233248123456');
  });

  test('does not mistake a local number starting 233 for a country code', () {
    // Glo Ghana's 023-3xx-xxxx range: bare local "233xxxxxx" is 9 digits,
    // not 12 — the country-code peel must not fire here.
    expect(normalizeGhPhone('233456789'), '+233233456789');
    expect(normalizeGhPhone('0233456789'), '+233233456789');
  });

  test('self-heals the malformed +2330… form if fed back through', () {
    expect(normalizeGhPhone('+2330592824972'), '+233592824972');
  });
}
