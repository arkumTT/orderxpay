import 'package:flutter_test/flutter_test.dart';
import 'package:orderxpay_mobile/core/invoice_calc.dart';

/// These expectations are the same numbers asserted in the Go test
/// (src/api/internal/http/handlers/invoice_engine_test.go). They are
/// duplicated deliberately: if the two calculators ever drift apart, the
/// merchant's preview stops matching the invoice they actually issue.
void main() {
  test('customer pays the fee — merchant receives exactly the asking price', () {
    final a = computeInvoiceAmounts(
      subtotalPesewas: 10000,
      commissionBps: 250,
      allocation: 'customer_only',
    );
    expect(a.totalPesewas, 10256);
    expect(a.commissionPesewas, 256);
    expect(a.serviceChargePesewas, 256);
    expect(a.merchantNetPesewas, 10000);
  });

  test('merchant absorbs the fee — customer pays the sticker price', () {
    final a = computeInvoiceAmounts(
      subtotalPesewas: 10000,
      commissionBps: 250,
      allocation: 'merchant_only',
    );
    expect(a.totalPesewas, 10000);
    expect(a.commissionPesewas, 250);
    expect(a.serviceChargePesewas, 0);
    expect(a.merchantNetPesewas, 9750);
  });

  test('split 50/50 — customer covers half the commission', () {
    final a = computeInvoiceAmounts(
      subtotalPesewas: 10000,
      commissionBps: 250,
      allocation: 'split',
      splitBps: 5000,
    );
    expect(a.totalPesewas, 10127);
    expect(a.commissionPesewas, 253);
    expect(a.serviceChargePesewas, 127);
    expect(a.merchantNetPesewas, 9874);
  });

  test('bundled delivery is part of the commission base', () {
    final a = computeInvoiceAmounts(
      subtotalPesewas: 2000,
      commissionBps: 250,
      allocation: 'customer_only',
      deliveryFeePesewas: 5000,
      deliveryBundled: true,
    );
    expect(a.totalPesewas, 7179);
    expect(a.commissionPesewas, 179);
    expect(a.merchantNetPesewas, 7000);

    // The regression: 1.95% of the total has to come out of the commission
    // and still leave something over.
    expect(a.commissionPesewas - (a.totalPesewas * 195 ~/ 10000), greaterThan(0));
  });

  test('external delivery is not commissioned', () {
    final a = computeInvoiceAmounts(
      subtotalPesewas: 10000,
      commissionBps: 250,
      allocation: 'customer_only',
      deliveryFeePesewas: 5000,
    );
    expect(a.totalPesewas, 10256);
    expect(a.commissionPesewas, 256);
  });

  test('subtotal + service charge + bundled delivery always equals the total', () {
    for (final allocation in ['customer_only', 'merchant_only', 'split']) {
      final a = computeInvoiceAmounts(
        subtotalPesewas: 7500,
        commissionBps: 400,
        allocation: allocation,
        splitBps: 3000,
        deliveryFeePesewas: 2500,
        deliveryBundled: true,
      );
      expect(7500 + a.serviceChargePesewas + 2500, a.totalPesewas,
          reason: 'reconciliation failed for $allocation');
    }
  });
}
