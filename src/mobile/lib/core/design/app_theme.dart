import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Spacing/radius tokens: 8px unit, 16-20px section padding, 16px cards,
/// 12px buttons/inputs, full pill on badges/chips/FAB.
class AppRadius {
  AppRadius._();
  static const double card = 16;
  static const double control = 12;
  static const pill = 9999.0;
}

class AppSpace {
  AppSpace._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
}

final ThemeData appTheme = ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: AppColors.background,
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    primary: AppColors.accent,
    surface: AppColors.surface,
  ),
  textTheme: GoogleFonts.urbanistTextTheme().apply(
    bodyColor: AppColors.primaryBlack,
    displayColor: AppColors.primaryBlack,
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: AppColors.background,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    centerTitle: true,
    iconTheme: const IconThemeData(color: AppColors.primaryBlack),
    titleTextStyle: GoogleFonts.urbanist(
      color: AppColors.primaryBlack,
      fontSize: 16,
      fontWeight: FontWeight.w700,
    ),
  ),
  dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
  splashFactory: NoSplash.splashFactory,
  highlightColor: Colors.transparent,
);
