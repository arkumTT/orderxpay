import 'package:flutter/material.dart';

/// The "OrderxPay" wordmark — the actual brand logotype asset (see
/// assets/branding/wordmark_logo.png), used anywhere a screen's title
/// text would otherwise just be the string "OrderxPay" (the onboarding
/// and login screens' headers, currently). Sized by height, not
/// fontSize — the asset's own aspect ratio (~4:1) determines the width.
class OxpWordmark extends StatelessWidget {
  const OxpWordmark({super.key, this.height = 32});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/branding/wordmark_logo.png',
      height: height,
      fit: BoxFit.contain,
      semanticLabel: 'OrderxPay',
    );
  }
}
