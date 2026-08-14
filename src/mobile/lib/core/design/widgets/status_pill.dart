import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../app_theme.dart';

/// 12%-tint-fill / full-strength-text pill for invoice and order-request
/// statuses. [color] drives both; label is whatever the caller wants shown
/// (backend status strings vs. design copy don't always match 1:1).
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  factory StatusPill.forInvoiceStatus(String status) {
    final (label, color) = switch (status) {
      'paid' => ('Paid', AppColors.statusPaid),
      'partially_paid' => ('Partial', AppColors.statusPartial),
      'sent' || 'viewed' => ('Pending', AppColors.statusPending),
      'draft' => ('Draft', AppColors.textSecondary),
      'expired' || 'cancelled' => ('Declined', AppColors.statusDeclined),
      'refunded' => ('Refunded', AppColors.statusPartial),
      _ => (status, AppColors.textSecondary),
    };
    return StatusPill(label: label, color: color);
  }

  factory StatusPill.forKYCStatus(String status) {
    final (label, color) = switch (status) {
      'approved' => ('Approved', AppColors.statusPaid),
      'rejected' => ('Rejected', AppColors.statusDeclined),
      'more_info_requested' => ('More info needed', AppColors.statusPartial),
      'pending' => ('Pending review', AppColors.statusPending),
      _ => (status, AppColors.textSecondary),
    };
    return StatusPill(label: label, color: color);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
