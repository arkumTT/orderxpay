import 'package:flutter/material.dart';
import '../app_colors.dart';

/// The "OrderxPay" wordmark, styled per the design spec — the "x" in
/// accent orange, everything else in the primary black. Text-based rather
/// than an image asset: simpler, scales cleanly, no binary asset to keep
/// in sync.
class OxpWordmark extends StatelessWidget {
  const OxpWordmark({super.key, this.fontSize = 32});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      color: AppColors.primaryBlack,
      letterSpacing: -0.5,
    );
    return RichText(
      text: TextSpan(
        style: style,
        children: [
          const TextSpan(text: 'Order'),
          TextSpan(text: 'x', style: style.copyWith(color: AppColors.accent)),
          const TextSpan(text: 'Pay'),
        ],
      ),
    );
  }
}
