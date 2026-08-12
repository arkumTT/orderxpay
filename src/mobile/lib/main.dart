import 'package:flutter/material.dart';
import 'core/theme.dart';
import 'features/home/screens/home_screen.dart';
import 'features/onboarding/screens/onboarding_screen.dart';
import 'features/catalog/screens/catalog_screen.dart';
import 'features/invoices/screens/invoices_screen.dart';
import 'features/messaging/screens/messaging_screen.dart';
import 'features/order_requests/screens/order_requests_screen.dart';
import 'features/records/screens/records_screen.dart';
import 'features/settings/screens/fee_settings_screen.dart';
import 'features/settings/screens/notifications_screen.dart';
import 'features/staff/screens/staff_screen.dart';
import 'features/delivery/screens/delivery_screen.dart';

void main() {
  runApp(const OrderxPayApp());
}

class OrderxPayApp extends StatelessWidget {
  const OrderxPayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OrderxPay',
      theme: appTheme,
      // TODO: gate initialRoute on session state once OTP sign-in exists
      // (Section 4.1) — currently always starts at onboarding.
      initialRoute: '/onboarding',
      routes: {
        '/onboarding': (context) => const OnboardingScreen(),
        '/': (context) => const HomeScreen(),
        '/catalog': (context) => const CatalogScreen(),
        '/invoices': (context) => const InvoicesScreen(),
        '/messaging': (context) => const MessagingScreen(),
        '/order-requests': (context) => const OrderRequestsScreen(),
        '/records': (context) => const RecordsScreen(),
        '/settings': (context) => const FeeSettingsScreen(),
        '/notifications': (context) => const NotificationsScreen(),
        '/staff': (context) => const StaffScreen(),
        '/delivery': (context) => const DeliveryScreen(),
      },
    );
  }
}
