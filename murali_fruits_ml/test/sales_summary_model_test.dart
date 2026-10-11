import 'package:flutter_test/flutter_test.dart';
import 'package:murali_fruits_ml/models/sales_summary_model.dart';

void main() {
  test('sales summary parser keeps safe defaults for optional missing values', () {
    final summary = SalesSummary.fromMap(<String, dynamic>{
      'created_date': '2026-01-02',
    });

    expect(summary.dayOfWeek, '');
    expect(summary.totalRevenue, 0);
    expect(summary.transactionCount, 0);
  });
}
