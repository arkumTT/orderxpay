import 'package:flutter/material.dart';
import '../../../core/placeholder_screen.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Notifications',
      section: '4.10',
      description:
          'Push/SMS/WhatsApp alerts: payment received, order request pending, '
          'payout processed, KYC status change.',
    );
  }
}
