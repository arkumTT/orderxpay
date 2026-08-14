import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../app_theme.dart';

enum OxpButtonVariant { primary, secondary, pay }

/// Full-width 52px button, 12px radius — the design system's one shape for
/// every primary action. [variant] picks the fill: primary = accent orange,
/// secondary = black outline, pay = green (Customer Checkout only, so a real
/// money transaction visually reads as distinct from internal app actions).
class OxpButton extends StatelessWidget {
  const OxpButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = OxpButtonVariant.primary,
    this.loading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final OxpButtonVariant variant;
  final bool loading;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || loading;
    final bg = switch (variant) {
      OxpButtonVariant.primary => AppColors.accent,
      OxpButtonVariant.pay => AppColors.payGreen,
      OxpButtonVariant.secondary => Colors.transparent,
    };
    final fg = switch (variant) {
      OxpButtonVariant.secondary => AppColors.primaryBlack,
      _ => Colors.white,
    };

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: disabled && variant != OxpButtonVariant.secondary
              ? bg.withValues(alpha: 0.5)
              : bg,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: variant == OxpButtonVariant.secondary
              ? Border.all(color: AppColors.primaryBlack, width: 1.5)
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.control),
            onTap: disabled ? null : onPressed,
            child: Center(
              child: loading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: fg,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            color: fg,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (icon != null) ...[
                          const SizedBox(width: 8),
                          icon!,
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
