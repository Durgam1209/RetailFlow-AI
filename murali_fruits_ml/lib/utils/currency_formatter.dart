import 'package:intl/intl.dart';

final NumberFormat _rupeeFormat = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);

String formatRupees(num value) => _rupeeFormat.format(value);
