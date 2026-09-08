/// Client-side preview mirroring internal/http/handlers/invoice_engine.go's
/// computeInvoiceAmounts — the server recomputes and is authoritative; this
/// is only for showing a live total before the user submits. Any change
/// here has to land in the Go version in the same breath, or the merchant's
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

InvoiceAmounts computeInvoiceAmounts({
  required int subtotalPesewas,
  required int commissionBps,
  required String allocation,
  int? splitBps,
  int deliveryFeePesewas = 0,
  bool deliveryBundled = false,
}) {
  // The commission base is everything that moves through the PSP: goods
  // plus a bundled delivery fee. An "external" delivery fee is settled
  // between customer and courier and never reaches the invoice total.
  var base = subtotalPesewas;
  if (deliveryBundled) base += deliveryFeePesewas;

  // Gross-up rather than a flat add-on, so the merchant receives exactly
  // their asking price: total = base / (1 - rate x customerShare).
  final effectiveBps =
      commissionBps * _customerCommissionShareBps(allocation, splitBps) ~/ 10000;
  final denominator = 10000 - effectiveBps;

  var total = base;
  if (denominator > 0 && denominator < 10000) {
    total = (base * 10000 + denominator ~/ 2) ~/ denominator;
  }

  return InvoiceAmounts(
    commissionPesewas: total * commissionBps ~/ 10000,
    serviceChargePesewas: total - base,
    totalPesewas: total,
  );
}
