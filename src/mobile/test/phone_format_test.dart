import 'package:flutter_test/flutter_test.dart';
import 'package:orderxpay_mobile/core/phone_format.dart';

/// Shared by OnboardingScreen (signup) and ApiClient.login (login) — the
/// point of this test is that both paths produce the exact same string
/// for the exact same typed number, since that string is what has to
/// match between CreateMerchant's stored phone and MerchantLogin's lookup.
void main() {
  test('prepends +233 to a bare local number', () {
    expect(normalizeGhPhone('205537712'), '+233205537712');
  });

  test('strips spaces before prepending +233', () {
    expect(normalizeGhPhone('20 553 7712'), '+233205537712');
  });

  test('leaves an already-+233-qualified number untouched', () {
    expect(normalizeGhPhone('+233205537712'), '+233205537712');
  });

  test('does not double-prefix a +233 number typed with spaces', () {
    expect(normalizeGhPhone('+233 20 553 7712'), '+233205537712');
  });
}
