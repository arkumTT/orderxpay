import 'dart:async';

import 'package:flutter/material.dart';
import 'core/app_navigator.dart';
import 'core/biometric_lock.dart';
import 'core/design/app_theme.dart';
import 'core/push_notifications.dart';
import 'core/session.dart';
import 'features/home/screens/home_screen.dart';
import 'features/onboarding/screens/biometric_lock_screen.dart';
import 'features/onboarding/screens/login_screen.dart';
import 'features/onboarding/screens/onboarding_screen.dart';
import 'features/catalog/screens/catalog_screen.dart';
import 'features/catalog/screens/catalog_sync_screen.dart';
import 'features/invoices/screens/new_order_screen.dart';
import 'features/messaging/screens/messaging_screen.dart';
import 'features/order_requests/screens/order_requests_screen.dart';
import 'features/records/screens/records_screen.dart';
import 'features/settings/screens/fee_settings_screen.dart';
import 'features/settings/screens/notifications_screen.dart';
import 'features/settings/screens/security_screen.dart';
import 'features/settings/screens/add_email_screen.dart';
import 'features/staff/screens/staff_screen.dart';
import 'features/delivery/screens/delivery_screen.dart';
import 'features/locations/screens/locations_screen.dart';
import 'features/customers/screens/customers_screen.dart';
import 'features/verify/screens/verify_screen.dart';
import 'features/more/screens/more_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Session.instance.load();
  await BiometricLock.instance.load();
  await PushNotifications.instance.init();
  if (Session.instance.isSignedIn) {
    // Already signed in from a previous launch — (re-)register this
    // device's token rather than waiting for a fresh login, since FCM
    // tokens can rotate between app launches.
    unawaited(PushNotifications.instance.registerToken());
  }

  // Biometric unlock (see biometric_lock_screen.dart) sits in front of an
  // already-signed-in session, not instead of login — a signed-out device
  // always lands on /login regardless of whether the toggle is on.
  final initialRoute = !Session.instance.isSignedIn
      ? '/login'
      : BiometricLock.instance.enabled
      ? '/biometric-lock'
      : '/';

  runApp(OrderxPayApp(initialRoute: initialRoute));
}

class OrderxPayApp extends StatefulWidget {
  const OrderxPayApp({super.key, required this.initialRoute});

  final String initialRoute;

  @override
  State<OrderxPayApp> createState() => _OrderxPayAppState();
}

class _OrderxPayAppState extends State<OrderxPayApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Auto-lock (More > Security): backgrounding the app starts a clock;
  // coming back past the configured grace period pushes the biometric lock
  // screen as an overlay on top of wherever the app was left, rather than
  // waiting for a full process restart the way the cold-start gate
  // (main()'s initialRoute) does. A quick app-switch under the grace
  // period — checking a notification, answering a call — doesn't re-lock,
  // which is the entire point of the timer being configurable.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        BiometricLock.instance.backgroundedAt = DateTime.now();
      case AppLifecycleState.resumed:
        if (!Session.instance.isSignedIn || !BiometricLock.instance.enabled) return;
        if (!BiometricLock.instance.shouldRelockNow()) return;
        PushNotifications.navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const BiometricLockScreen(isOverlay: true)),
        );
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OrderxPay',
      theme: appTheme,
      navigatorKey: appNavigatorKey,
      scaffoldMessengerKey: appMessengerKey,
      initialRoute: widget.initialRoute,
      routes: {
        '/login': (context) => const LoginScreen(),
        '/onboarding': (context) => const OnboardingScreen(),
        '/biometric-lock': (context) => const BiometricLockScreen(),
        '/': (context) => const HomeScreen(),
        '/catalog': (context) => const CatalogScreen(),
        '/catalog-sync': (context) => const CatalogSyncScreen(),
        '/new-order': (context) => const NewOrderScreen(),
        '/messaging': (context) => const MessagingScreen(),
        '/order-requests': (context) => const OrderRequestsScreen(),
        '/records': (context) => const RecordsScreen(),
        '/settings': (context) => const FeeSettingsScreen(),
        '/notifications': (context) => const NotificationsScreen(),
        '/staff': (context) => const StaffScreen(),
        '/delivery': (context) => const DeliveryScreen(),
        '/locations': (context) => const LocationsScreen(),
        '/customers': (context) => const CustomersScreen(),
        '/verify': (context) => const VerifyScreen(),
        '/security': (context) => const SecurityScreen(),
        '/add-email': (context) => const AddEmailScreen(),
        '/more': (context) => const MoreScreen(),
      },
    );
  }
}
