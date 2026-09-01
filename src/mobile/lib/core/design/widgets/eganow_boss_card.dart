import 'package:flutter/material.dart';
import 'eganow_card_face.dart';

/// The Eganow Boss card face (`assets/images/eganow_boss_card.png`).
///
/// Pass [cardNumber], [cardholderName] and [expiry] to overlay live card
/// data in the blank lower half of the design, the way a wallet/virtual
/// card screen would. Omit them to show the bare card face.
class EganowBossCard extends StatelessWidget {
  const EganowBossCard({
    super.key,
    this.cardNumber,
    this.cardholderName,
    this.expiry,
    this.width,
  });

  final String? cardNumber;
  final String? cardholderName;
  final String? expiry;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return EganowCardFace(
      asset: 'assets/images/eganow_boss_card.png',
      // Measured from the artwork's alpha channel.
      cornerRadiusFraction: 0.04,
      cardNumber: cardNumber,
      cardholderName: cardholderName,
      expiry: expiry,
      width: width,
    );
  }
}
