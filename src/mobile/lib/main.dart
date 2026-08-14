import 'package:flutter/material.dart';
import 'core/design/app_theme.dart';
import 'core/session.dart';
import 'features/home/screens/home_screen.dart';
import 'features/onboarding/screens/onboarding_screen.dart';
import 'features/catalog/screens/catalog_screen.dart';
import 'features/invoices/screens/new_order_screen.dart';
import 'features/messaging/screens/messaging_screen.dart';
import 'features/order_requests/screens/order_requests_screen.dart';
import 'features/records/screens/records_screen.dart';
import 'features/settings/screens/fee_settings_screen.dart';
import 'features/settings/screens/notifications_screen.dart';
import 'features/staff/screens/staff_screen.dart';
import 'features/delivery/screens/delivery_screen.dart';
import 'features/verify/screens/verify_screen.dart';
import 'features/more/screens/more_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Session.instance.load();
  runApp(OrderxPayApp(startSignedIn: Session.instance.isSignedIn));
}

class OrderxPayApp extends StatelessWidget {
  const OrderxPayApp({super.key, required this.startSignedIn});

  final bool startSignedIn;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OrderxPay',
      theme: appTheme,
      initialRoute: startSignedIn ? '/' : '/onboarding',
      routes: {
        '/onboarding': (context) => const OnboardingScreen(),
        '/': (context) => const HomeScreen(),
        '/catalog': (context) => const CatalogScreen(),
        '/new-order': (context) => const NewOrderScreen(),
        '/messaging': (context) => const MessagingScreen(),
        '/order-requests': (context) => const OrderRequestsScreen(),
        '/records': (context) => const RecordsScreen(),
        '/settings': (context) => const FeeSettingsScreen(),
        '/notifications': (context) => const NotificationsScreen(),
        '/staff': (context) => const StaffScreen(),
        '/delivery': (context) => const DeliveryScreen(),
        '/verify': (context) => const VerifyScreen(),
        '/more': (context) => const MoreScreen(),
      },
    );
  }
}
