import 'package:flutter/material.dart';

/// Design tokens from the OrderxPay Onboarding Design (Claude Design project
/// 03a84116-fa47-44aa-b4fe-ad66ab16e755) — a premium quick-service-app feel,
/// not generic fintech. Flat design: borders instead of shadows, one accent
/// color carrying every CTA.
class AppColors {
  AppColors._();

  static const Color primaryBlack = Color(0xFF0A0A0A);
  static const Color background = Color(0xFFF5F5F5);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color accent = Color(0xFFFF5F1F);
  static const Color accentPressed = Color(0xFFE0530F);

  static const Color textSecondary = Color(0xFF6B6B6B);
  static const Color textDisabled = Color(0xFFB8B8B8);
  static const Color border = Color(0xFFE5E5E5);
  static const Color fieldFill = Color(0xFFF2F2F2);

  // Status pills — 12% tint fill, full-strength text (see StatusPill).
  static const Color statusPaid = Color(0xFF1FAE6E);
  static const Color statusPending = Color(0xFFFF5F1F);
  static const Color statusDeclined = Color(0xFFD4553F);
  static const Color statusPartial = Color(0xFF3E7CC9);

  /// The one screen (Customer Checkout) where "pay" needs to read as a
  /// distinct, trustworthy action separate from the app's internal orange CTAs.
  static const Color payGreen = Color(0xFF1FAE6E);
}
