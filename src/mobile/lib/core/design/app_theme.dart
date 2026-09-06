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

/// The extra bottom inset a bottom-pinned button (a scrollable screen's
/// final action, or a bottom sheet's Save button) needs to clear the
/// device's system UI — the persistent nav bar/gesture area normally, or
/// the on-screen keyboard when one's up. Takes whichever is taller rather
/// than summing them: when the keyboard is showing it already exceeds any
/// nav bar height, so adding both would just leave extra dead space.
///
/// Caught live on a physical device with 3-button/gesture nav: buttons at
/// the bottom of several screens and bottom sheets sat flush against (or
/// under) the system nav bar because their padding only ever accounted
/// for `viewInsets.bottom` (the keyboard) or a plain fixed constant,
/// never `viewPadding.bottom` (the permanent system UI inset).
double bottomSafeInset(BuildContext context) {
  final mq = MediaQuery.of(context);
  return mq.viewInsets.bottom > mq.viewPadding.bottom
      ? mq.viewInsets.bottom
      : mq.viewPadding.bottom;
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
