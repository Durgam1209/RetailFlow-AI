import 'package:flutter_test/flutter_test.dart';
import 'package:murali_fruits_ml/utils/insight_parser.dart';

void main() {
  test('parses JSON lists and maps from Supabase fields', () {
    expect(parseInsightList('[{"fruit":"Apple"}]', field: 'stock_advice'), [
      {'fruit': 'Apple'},
    ]);
    expect(parseInsightMap('{"priority":"High"}', field: 'festival_advice'), {
      'priority': 'High',
    });
  });

  test('malformed and missing fields use safe fallbacks', () {
    expect(parseInsightList('{invalid', field: 'stock_advice'), isEmpty);
    expect(parseInsightMap(null, field: 'weather_advice'), isEmpty);
    expect(parseInsightSummary(12), 'Demand is steady.');
  });
}
