/// Client-side preview mirroring internal/http/handlers/invoice_engine.go's
/// computeInvoiceAmounts — the server recomputes and is authoritative; this
/// is only for showing a live total before the user submits.
class InvoiceAmounts {
  InvoiceAmounts({
    required this.commissionPesewas,
    required this.serviceChargePesewas,
    required this.totalPesewas,
  });

  final int commissionPesewas;
  final int serviceChargePesewas;
  final int totalPesewas;
}

InvoiceAmounts computeInvoiceAmounts({
  required int subtotalPesewas,
  required int commissionBps,
  required String allocation,
  int? splitBps,
  int deliveryFeePesewas = 0,
  bool deliveryBundled = false,
}) {
  final commission = subtotalPesewas * commissionBps ~/ 10000;

  int serviceCharge;
  switch (allocation) {
    case 'customer_only':
      serviceCharge = commission;
    case 'merchant_only':
      serviceCharge = 0;
    case 'split':
      final bps = splitBps ?? 0;
      serviceCharge = commission * bps ~/ 10000;
    default:
      serviceCharge = 0;
  }

  var total = subtotalPesewas + serviceCharge;
  if (deliveryBundled) total += deliveryFeePesewas;

  return InvoiceAmounts(
    commissionPesewas: commission,
    serviceChargePesewas: serviceCharge,
    totalPesewas: total,
  );
}
