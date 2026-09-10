import 'package:flutter_test/flutter_test.dart';
import 'package:orderxpay_mobile/core/pull_to_refresh.dart';

/// RefreshIndicator.onRefresh must never throw — an error there propagates
/// to the zone as an unhandled exception. settleForRefresh awaits the load
/// for the spinner's timing but absorbs any failure (the screen's own
/// FutureBuilder renders it; on a 401, ApiClient already redirected).
void main() {
  test('completes normally when the future succeeds', () async {
    await expectLater(settleForRefresh(Future<int>.value(42)), completes);
  });

  test('completes — does not rethrow — when the future fails', () async {
    await expectLater(
      settleForRefresh(Future<int>.error(Exception('load failed'))),
      completes,
    );
  });
}
