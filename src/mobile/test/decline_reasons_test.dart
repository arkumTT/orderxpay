import 'package:flutter_test/flutter_test.dart';
import 'package:orderxpay_mobile/core/decline_reasons.dart';

void main() {
  test(
      'every key has a label and an entry (possibly empty) in the canned-message map',
      () {
    for (final key in declineReasonKeys) {
      expect(declineReasonLabels.containsKey(key), true,
          reason: 'missing label for $key');
      expect(declineReasonCannedMessages.containsKey(key), true,
          reason: 'missing canned message entry for $key');
    }
  });

  group('declineMessageFor', () {
    test('a canned category with no note uses the canned line as-is', () {
      expect(declineMessageFor('out_of_stock', ''),
          "Sorry, this item isn't in stock right now.");
    });

    test('a canned category with a note appends it after the canned line', () {
      expect(
        declineMessageFor('out_of_stock', 'restocking Thursday'),
        "Sorry, this item isn't in stock right now. restocking Thursday",
      );
    });

    test('other has no canned line — the note alone is the whole message', () {
      expect(declineMessageFor('other', 'we no longer carry that brand'),
          'we no longer carry that brand');
    });

    test('a note is trimmed before being appended', () {
      expect(
        declineMessageFor('out_of_stock', '   back Thursday   '),
        "Sorry, this item isn't in stock right now. back Thursday",
      );
    });

    test('an unrecognized category with a note falls back to just the note',
        () {
      expect(
          declineMessageFor('not_a_real_category', 'some note'), 'some note');
    });
  });

  group('declineDeemphasizesNotifying', () {
    test('suspected_spam is the only category that flips the notify default',
        () {
      for (final key in declineReasonKeys) {
        expect(declineDeemphasizesNotifying(key), key == 'suspected_spam',
            reason: 'wrong default for $key');
      }
    });
  });
}
