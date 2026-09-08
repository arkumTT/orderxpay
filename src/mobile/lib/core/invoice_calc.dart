/// Client-side preview mirroring internal/http/handlers/invoice_engine.go's
/// computeInvoiceAmounts — the server recomputes and is authoritative; this
/// is only for showing a live total before the user submits. Any change here
/// has to land in the Go version in the same breath, or the merchant's
/// preview and their actual invoice will disagree.
class InvoiceAmounts {
  InvoiceAmounts({
    required this.commissionPesewas,
    required this.serviceChargePesewas,
    required this.totalPesewas,
  });

  final int commissionPesewas;
  final int serviceChargePesewas;
  final int totalPesewas;

  /// What the merchant banks once the platform takes its commission — the
  /// figure worth showing them, since it is the one they actually care about.
  int get merchantNetPesewas => totalPesewas - commissionPesewas;
}

/// How much of the commission the customer pays on top of the merchant's
/// asking price, in bps of the commission (10000 = the customer pays all of
/// it). An unrecognised allocation is treated as merchant_only, matching Go.
int _customerCommissionShareBps(String allocation, int? splitBps) {
  switch (allocation) {
    case 'customer_only':
      return 10000;
    case 'split':
      final share = splitBps ?? 0;
      if (share < 0) return 0;
      if (share > 10000) return 10000;
      return share;
    default:
      return 0;
  }
}

/// Solves total = amount / (1 - effectiveBps), rounding to the nearest
/// pesewa so the merchant is left exactly whole.
int _grossUp(int amount, int effectiveBps) {
  final denominator = 10000 - effectiveBps;
  if (denominator <= 0 || denominator >= 10000) return amount;
  return (amount * 10000 + denominator ~/ 2) ~/ denominator;
}

InvoiceAmounts computeInvoiceAmounts({
  required int subtotalPesewas,
  required int collectionFeeBps,
  required int marginBps,
  required String allocation,
  int? splitBps,
  int marginFloorPesewas = 0,
  int marginCapPesewas = 0,
  int deliveryFeePesewas = 0,
  bool deliveryBundled = false,
}) {
  // The commission base is everything that moves through the payment
  // provider: goods plus a bundled delivery fee. An "external" delivery fee
  // is settled between customer and courier and never reaches the total.
  var base = subtotalPesewas;
  if (deliveryBundled) base += deliveryFeePesewas;
  if (base <= 0) {
    return InvoiceAmounts(
      commissionPesewas: 0,
      serviceChargePesewas: 0,
      totalPesewas: 0,
    );
  }

  final shareBps = _customerCommissionShareBps(allocation, splitBps);

  // Solve the unclamped case first, then re-solve against whichever clamp it
  // turns out to hit: with the margin pinned to a constant, the remaining
  // rate is just the pass-through, and the pinned amount grosses up
  // alongside the base.
  var total = _grossUp(base, (collectionFeeBps + marginBps) * shareBps ~/ 10000);
  final collectionOnlyBps = collectionFeeBps * shareBps ~/ 10000;

  final unclamped = total * marginBps ~/ 10000;
  if (unclamped < marginFloorPesewas) {
    total = _grossUp(base + marginFloorPesewas * shareBps ~/ 10000, collectionOnlyBps);
  } else if (marginCapPesewas > 0 && unclamped > marginCapPesewas) {
    total = _grossUp(base + marginCapPesewas * shareBps ~/ 10000, collectionOnlyBps);
  }

  var margin = total * marginBps ~/ 10000;
  if (margin < marginFloorPesewas) margin = marginFloorPesewas;
  if (marginCapPesewas > 0 && margin > marginCapPesewas) margin = marginCapPesewas;

  var commission = total * collectionFeeBps ~/ 10000 + margin;
  // Taking more than was collected would push the merchant payout negative.
  if (commission > total) commission = total;

  return InvoiceAmounts(
    commissionPesewas: commission,
    serviceChargePesewas: total - base,
    totalPesewas: total,
  );
}
