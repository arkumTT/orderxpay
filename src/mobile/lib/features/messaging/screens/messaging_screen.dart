import 'package:flutter/material.dart';
import '../../../core/placeholder_screen.dart';

class MessagingScreen extends StatelessWidget {
  const MessagingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Messaging & Distribution',
      section: '4.4',
      description:
          'Send the invoice/payment link via SMS, WhatsApp, email, or copy link. '
          'Delivery status per channel. Template library for common messages.',
    );
  }
}
