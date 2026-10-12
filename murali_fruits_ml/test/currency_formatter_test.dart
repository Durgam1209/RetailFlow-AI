import 'package:flutter_test/flutter_test.dart';
import 'package:murali_fruits_ml/utils/currency_formatter.dart';

void main() {
  test('formats rupees with Indian digit grouping', () {
    expect(formatRupees(32176), '₹32,176');
    expect(formatRupees(1234567), '₹12,34,567');
  });
}
