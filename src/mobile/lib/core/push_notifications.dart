import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_client.dart';
import 'app_navigator.dart';
import 'session.dart';

/// Section 4.10 Phase 2 — push notifications via Firebase Cloud Messaging,
/// Android only for now (see the backend's internal/fcm doc comment on why
/// iOS is deferred: it needs a paid Apple Developer Program account and
/// APNs certs this project doesn't have). Phase 1 (the in-app bell +
/// order-request banner on Home) already works without any of this; this
/// module is purely additive on top of it.
///
/// A notification tap — which happens outside any widget's BuildContext,
/// possibly before the app has even finished launching — navigates through
/// the app-wide [appNavigatorKey] (see app_navigator.dart).
class PushNotifications {
  PushNotifications._();
  static final PushNotifications instance = PushNotifications._();

  /// Kept as an alias for existing call sites; the key itself now lives in
  /// app_navigator.dart so ApiClient can reach it too, without pulling in
  /// Firebase.
  static GlobalKey<NavigatorState> get navigatorKey => appNavigatorKey;

  final _local = FlutterLocalNotificationsPlugin();
  static const _channel = AndroidNotificationChannel(
    'orderxpay_default',
    'OrderxPay notifications',
    description: 'Order requests, payments, payouts, and verification updates',
    importance: Importance.high,
  );

  bool _initialized = false;

  /// Called once at app startup (see main.dart), regardless of sign-in
  /// state — sets up the notification channel and foreground/tap
  /// listeners, but doesn't register a token with the backend (that needs
  /// a merchant id, see [registerToken]).
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_backgroundHandler);

    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null) _navigateFor(payload);
      },
    );

    // Foreground: FCM delivers the message but doesn't show a system
    // notification itself (that only happens automatically when the app is
    // backgrounded/terminated) — show one via flutter_local_notifications
    // so a merchant using the app right now still sees it.
    FirebaseMessaging.onMessage.listen(_showForegroundNotification);

    // Tapped from the background (app was running, just not foregrounded).
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _navigateFor(message.data['target_entity'] as String?);
    });

    // Tapped from fully terminated (cold start) — the tapped notification
    // that launched the app, if any.
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _navigateFor(initialMessage.data['target_entity'] as String?);
    }
  }

  void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;
    _local.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: message.data['target_entity'] as String?,
    );
  }

  void _navigateFor(String? targetEntity) {
    final route = switch (targetEntity) {
      'order_request' => '/order-requests',
      'kyc_submission' => '/verify',
      'invoice' || 'settlement' => '/records',
      _ => '/notifications',
    };
    navigatorKey.currentState?.pushNamed(route);
  }

  /// Requests notification permission and registers this device's FCM
  /// token with the backend — call after a successful login, and again on
  /// every cold start while already signed in (see home_screen.dart). Also
  /// listens for FCM's own token-rotation event and re-registers.
  Future<void> registerToken() async {
    final merchantId = Session.instance.merchantId;
    if (merchantId == null) return;

    final settings = await FirebaseMessaging.instance.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _register(merchantId, token);
    }
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      final currentMerchantId = Session.instance.merchantId;
      if (currentMerchantId != null) _register(currentMerchantId, newToken);
    });
  }

  Future<void> _register(String merchantId, String token) async {
    try {
      await ApiClient().registerDeviceToken(merchantId, token);
    } catch (_) {
      // Best-effort — the in-app notification feed (Phase 1) still works
      // regardless of whether push registration succeeds.
    }
  }

  /// Called on sign-out (see more_screen.dart), before the session is
  /// cleared — unregisters this device's token so it stops receiving
  /// pushes for a merchant it's no longer logged into.
  Future<void> unregisterToken() async {
    final merchantId = Session.instance.merchantId;
    if (merchantId == null) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await ApiClient().unregisterDeviceToken(merchantId, token);
      }
    } catch (_) {
      // Best-effort — signing out must never be blocked by this.
    }
  }
}

// Must be a top-level function, not a method — the background handler
// runs in its own isolate and needs to re-initialize Firebase there.
@pragma('vm:entry-point')
Future<void> _backgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}
