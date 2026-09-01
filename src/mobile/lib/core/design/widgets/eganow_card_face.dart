import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shared renderer behind the Eganow card widgets ([EganowFreedomCard],
/// [EganowBossCard], ...): draws a pre-rendered card asset — chip,
/// contactless mark and wordmark are baked into the image, corners are
/// pre-rounded via a transparent alpha channel — and overlays optional
/// card number/holder/expiry text in the artwork's blank lower half, the
/// way a wallet/virtual-card screen would.
///
/// Not exported from the design system directly; each card variant wraps
/// this with its own asset path and corner radius.
class EganowCardFace extends StatelessWidget {
  const EganowCardFace({
    super.key,
    required this.asset,
    required this.cornerRadiusFraction,
    this.cardNumber,
    this.cardholderName,
    this.expiry,
    this.width,
  });

  final String asset;

  /// The artwork's rounded-corner radius as a fraction of its width —
  /// measured from the source PNG's alpha channel per variant, since it
  /// isn't identical across designs. Used so the drop shadow hugs the
  /// card's actual edge.
  final double cornerRadiusFraction;

  /// e.g. `"•••• •••• •••• 4821"`.
  final String? cardNumber;

  final String? cardholderName;

  /// e.g. `"09/28"`.
  final String? expiry;

  /// Renders full-width of its parent when null.
  final double? width;

  static const double aspectRatio = 2016 / 1278;

  @override
  Widget build(BuildContext context) {
    final card = AspectRatio(
      aspectRatio: aspectRatio,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = w / aspectRatio;
          final textShadow = [
            Shadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: w * 0.01),
          ];

          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(w * cornerRadiusFraction),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: w * 0.05,
                  offset: Offset(0, w * 0.02),
                ),
              ],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(asset, fit: BoxFit.cover),
                if (cardNumber != null)
                  Positioned(
                    left: w * 0.09,
                    right: w * 0.09,
                    top: h * 0.60,
                    child: Text(
                      cardNumber!,
                      style: GoogleFonts.robotoMono(
                        color: Colors.white,
                        fontSize: w * 0.062,
                        fontWeight: FontWeight.w600,
                        letterSpacing: w * 0.006,
                        shadows: textShadow,
                      ),
                    ),
                  ),
                if (cardholderName != null || expiry != null)
                  Positioned(
                    left: w * 0.09,
                    right: w * 0.09,
                    bottom: h * 0.09,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (cardholderName != null)
                          Flexible(
                            child: _Label(
                              label: 'CARD HOLDER',
                              value: cardholderName!.toUpperCase(),
                              width: w,
                              shadows: textShadow,
                            ),
                          ),
                        if (expiry != null) ...[
                          SizedBox(width: w * 0.04),
                          _Label(
                            label: 'EXPIRES',
                            value: expiry!,
                            width: w,
                            shadows: textShadow,
                            alignEnd: true,
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );

    if (width == null) return card;
    return SizedBox(width: width, child: card);
  }
}

class _Label extends StatelessWidget {
  const _Label({
    required this.label,
    required this.value,
    required this.width,
    required this.shadows,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final double width;
  final List<Shadow> shadows;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: GoogleFonts.urbanist(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: width * 0.025,
            fontWeight: FontWeight.w600,
            letterSpacing: width * 0.003,
            shadows: shadows,
          ),
        ),
        SizedBox(height: width * 0.008),
        Text(
          value,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.urbanist(
            color: Colors.white,
            fontSize: width * 0.038,
            fontWeight: FontWeight.w700,
            letterSpacing: width * 0.002,
            shadows: shadows,
          ),
        ),
      ],
    );
  }
}
