import 'package:intl/intl.dart';

/// Money is always int pesewas (GHS lowest unit) over the wire — never doubles.
String formatPesewas(int pesewas) {
  final format = NumberFormat.currency(
    locale: 'en_GH',
    symbol: 'GH₵',
    decimalDigits: 2,
  );
  return format.format(pesewas / 100);
}

/// Compact label for tight spaces (chart bars) — no decimals, "k" for
/// thousands, e.g. 520 -> "5", 125000 -> "1.3k".
String formatPesewasShort(int pesewas) {
  final ghs = pesewas / 100;
  if (ghs >= 1000) return '${(ghs / 1000).toStringAsFixed(1)}k';
  return ghs.round().toString();
}
