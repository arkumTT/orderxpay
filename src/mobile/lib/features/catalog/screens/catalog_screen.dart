import 'package:flutter/material.dart';
import '../../../core/placeholder_screen.dart';

class CatalogScreen extends StatelessWidget {
  const CatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Catalog & Item Management',
      section: '4.2',
      description:
          'Preset item library: name, unit price, quantity/unit type, category, '
          'image upload, availability toggle. Quick-add for one-off custom items. '
          'This same catalog powers the hosted catalog page (Section 4.6).',
    );
  }
}
