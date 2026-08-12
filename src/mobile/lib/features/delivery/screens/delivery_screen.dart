import 'package:flutter/material.dart';
import '../../../core/placeholder_screen.dart';

class DeliveryScreen extends StatelessWidget {
  const DeliveryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Delivery Coordination',
      section: '4.11',
      description:
          'Tier 1: merchant\'s own delivery contact. Tier 2: deep-link directory '
          'to verified third-party delivery apps. Configurable per order, not '
          'fixed platform-wide.',
    );
  }
}
