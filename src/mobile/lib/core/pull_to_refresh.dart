/// Every screen's `RefreshIndicator.onRefresh` follows the same shape:
/// kick off a fresh load, stash the Future in `_future` for the
/// FutureBuilder, then `await` it purely so the indicator knows when to
/// stop spinning. That last `await` must not surface an error —
/// RefreshIndicator doesn't consume one, so it propagates to the zone as
/// an unhandled exception. And it doesn't need to: the screen's own
/// FutureBuilder renders load failures, and on a 401 ApiClient has already
/// cleared the session and redirected to Login. So: await for the
/// spinner's sake, swallow here.
Future<void> settleForRefresh(Future<Object?> future) async {
  try {
    await future;
  } catch (_) {
    // intentionally swallowed — see the doc comment above
  }
}
