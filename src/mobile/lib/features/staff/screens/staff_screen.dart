import 'package:flutter/material.dart';
import '../../../core/placeholder_screen.dart';

class StaffScreen extends StatelessWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Multi-User / Staff Roles',
      section: '4.9',
      description:
          'Staff role: can create/send invoices, cannot change payout settings '
          'or view full KYC/bank details.',
    );
  }
}
