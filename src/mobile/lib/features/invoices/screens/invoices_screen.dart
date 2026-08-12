import 'package:flutter/material.dart';
import '../../../core/placeholder_screen.dart';

class InvoicesScreen extends StatelessWidget {
  const InvoicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Order & Invoice Engine',
      section: '4.3',
      description:
          'Build an order from the catalog or a quick custom line item. Generates '
          'a shareable invoice with a payment link/QR. Lifecycle: Draft → Sent → '
          'Viewed → Partially Paid → Paid → Expired/Cancelled → Refunded.',
    );
  }
}
