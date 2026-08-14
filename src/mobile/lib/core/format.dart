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
