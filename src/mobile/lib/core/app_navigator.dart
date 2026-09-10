import 'package:flutter/material.dart';

/// The app's single navigator key — wired to MaterialApp in main.dart so
/// code outside the widget tree can drive navigation: PushNotifications on
/// a notification tap, and ApiClient when a request comes back 401 and the
/// user needs to be bounced back to the Login screen.
final appNavigatorKey = GlobalKey<NavigatorState>();

/// Wired to MaterialApp alongside the navigator key, so ApiClient can put a
/// "your session expired" SnackBar in front of the Login screen it just
/// redirected to — showing a SnackBar needs a messenger, and there's no
/// BuildContext this far from the tree.
final appMessengerKey = GlobalKey<ScaffoldMessengerState>();
