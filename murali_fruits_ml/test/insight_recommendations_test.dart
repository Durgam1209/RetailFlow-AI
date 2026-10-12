import 'package:flutter_test/flutter_test.dart';
import 'package:murali_fruits_ml/utils/insight_recommendations.dart';

void main() {
  test('rounds recommendations to half kilograms and hides small items', () {
    expect(recommendationQuantityKg({'suggested_kg': 2.24}), 2.0);
    expect(recommendationQuantityKg({'suggested_kg': 2.26}), 2.5);
    expect(recommendationQuantityKg({'suggested_kg': 0.8}), isNull);
  });

  test('prefers recommended_order_qty when supplied', () {
    expect(
      recommendationQuantityKg({
        'recommended_order_qty': 4.76,
        'suggested_kg': 2.0,
      }),
      5.0,
    );
  });

  test('uses evidence for forecast and bundle confidence labels', () {
    expect(bundleConfidenceLabel(19), 'Low confidence');
    expect(bundleConfidenceLabel(20), 'Medium confidence');
    expect(
      forecastConfidenceLabel({'beats_baseline': true, 'wape_pct': 20}),
      'High confidence',
    );
    expect(forecastConfidenceLabel({'history_days': 14}), 'Low confidence');
  });
}
