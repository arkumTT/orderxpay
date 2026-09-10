import 'package:flutter_test/flutter_test.dart';
import 'package:orderxpay_mobile/core/invoice_calc.dart';

/// These expectations are the same numbers asserted in the Go test
/// (src/api/internal/http/handlers/invoice_engine_test.go). They are
/// duplicated deliberately: if the two calculators ever drift apart, the
/// merchant's preview stops matching the invoice they actually issue.
///
/// The model under test: 1.95% passed through to the payment provider,
/// 0.55% kept, floored at GHS 0.20 and capped at GHS 25.00 per invoice.
InvoiceAmounts amounts({
  required int subtotal,
  required String allocation,
  int? splitBps,
  int deliveryFee = 0,
  bool bundled = false,
}) =>
    computeInvoiceAmounts(
      subtotalPesewas: subtotal,
      collectionFeeBps: 195,
      marginBps: 55,
      marginFloorPesewas: 20,
      marginCapPesewas: 2500,
      allocation: allocation,
      splitBps: splitBps,
      deliveryFeePesewas: deliveryFee,
      deliveryBundled: bundled,
    );

int pspCost(int total) => total * 195 ~/ 10000;

void main() {
  group('merchantNetNote', () {
    test('customer covers the fee — net matches the ask', () {
      expect(
        merchantNetNote(ask: 10000, net: 10001), // gross-up leaves a spare pesewa
        'Your full price — the customer covers our fee',
      );
      expect(merchantNetNote(ask: 10000, net: 10000),
          'Your full price — the customer covers our fee');
    });

    test('merchant absorbs part of the fee — names the amount', () {
      expect(merchantNetNote(ask: 10000, net: 9750), 'After GH₵2.50 in fees');
    });
  });

  test('customer pays the fee — merchant is left whole', () {
    final a = amounts(subtotal: 10000, allocation: 'customer_only');
    expect(a.totalPesewas, 10256);
    expect(a.commissionPesewas, 255);
    expect(a.serviceChargePesewas, 256);
    expect(a.merchantNetPesewas, 10001);
  });

  test('merchant absorbs the fee — customer pays the sticker price', () {
    final a = amounts(subtotal: 10000, allocation: 'merchant_only');
    expect(a.totalPesewas, 10000);
    expect(a.commissionPesewas, 250);
    expect(a.serviceChargePesewas, 0);
    expect(a.merchantNetPesewas, 9750);
  });

  test('split 50/50 — customer covers half the commission', () {
    final a = amounts(subtotal: 10000, allocation: 'split', splitBps: 5000);
    expect(a.totalPesewas, 10127);
    expect(a.commissionPesewas, 252);
    expect(a.serviceChargePesewas, 127);
    expect(a.merchantNetPesewas, 9875);
  });

  test('bundled delivery is part of the commission base', () {
    final a = amounts(
      subtotal: 2000,
      allocation: 'customer_only',
      deliveryFee: 5000,
      bundled: true,
    );
    expect(a.totalPesewas, 7179);
    expect(a.commissionPesewas, 178);
    expect(a.merchantNetPesewas, 7001);

    // The regression: the provider's cut of the whole total has to come out
    // of the commission and still leave something over.
    expect(a.commissionPesewas - pspCost(a.totalPesewas), greaterThan(0));
  });

  test('external delivery is not commissioned', () {
    final a = amounts(
      subtotal: 10000,
      allocation: 'customer_only',
      deliveryFee: 5000,
    );
    expect(a.totalPesewas, 10256);
    expect(a.commissionPesewas, 255);
  });

  test('small invoice — the margin floor applies', () {
    final a = amounts(subtotal: 500, allocation: 'customer_only');
    expect(a.totalPesewas, 530);
    expect(a.commissionPesewas, 30);
    expect(a.merchantNetPesewas, 500);
    expect(a.commissionPesewas - pspCost(a.totalPesewas), 20);
  });

  test('large invoice — the margin cap holds the effective rate down', () {
    final a = amounts(subtotal: 800000, allocation: 'customer_only');
    expect(a.commissionPesewas - pspCost(a.totalPesewas), 2500);

    final effectiveBps = a.serviceChargePesewas * 10000 ~/ 800000;
    expect(effectiveBps, lessThan(250));
    expect(effectiveBps, greaterThan(195));
  });

  test('a zero-value invoice is never charged the floor', () {
    final a = amounts(subtotal: 0, allocation: 'customer_only');
    expect(a.totalPesewas, 0);
    expect(a.commissionPesewas, 0);
    expect(a.serviceChargePesewas, 0);
  });

  test('subtotal + service charge + bundled delivery always equals the total', () {
    for (final allocation in ['customer_only', 'merchant_only', 'split']) {
      final a = amounts(
        subtotal: 7500,
        allocation: allocation,
        splitBps: 3000,
        deliveryFee: 2500,
        bundled: true,
      );
      expect(7500 + a.serviceChargePesewas + 2500, a.totalPesewas,
          reason: 'reconciliation failed for $allocation');
    }
  });
}
