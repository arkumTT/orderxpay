import 'package:flutter/material.dart';
import '../../../core/placeholder_screen.dart';

class RecordsScreen extends StatelessWidget {
  const RecordsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Records, Ledger & Reporting',
      section: '4.7',
      description:
          'Searchable, filterable records: customer, date/time, items, amount '
          'invoiced, amount paid, outstanding balance, status, channel used. '
          'Best-selling items, daily/weekly collections, CSV/PDF export.',
    );
  }
}
