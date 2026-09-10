import 'package:flutter/widgets.dart';

/// The app's single navigator key — wired to MaterialApp in main.dart so
/// code outside the widget tree can drive navigation: PushNotifications on
/// a notification tap, and ApiClient when a request comes back 401 and the
/// user needs to be bounced back to the Login screen.
final appNavigatorKey = GlobalKey<NavigatorState>();
