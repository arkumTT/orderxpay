import 'package:flutter/material.dart';
import 'design/app_colors.dart';
import 'design/app_theme.dart';

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    super.key,
    required this.title,
    required this.section,
    required this.description,
  });

  final String title;
  final String section;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Section $section',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpace.xxl),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: const Text(
                'Not yet implemented — structural placeholder only.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textDisabled),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
