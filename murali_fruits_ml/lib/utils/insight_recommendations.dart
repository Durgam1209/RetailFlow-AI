const double minimumRecommendationKg = 1.0;

double? recommendationQuantityKg(Map<String, dynamic> item) {
  final raw = item['recommended_order_qty'] ?? item['suggested_kg'];
  final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
  if (value == null || !value.isFinite || value < minimumRecommendationKg) {
    return null;
  }
  return roundToHalfKg(value);
}

double roundToHalfKg(double value) => (value * 2).round() / 2;

String? recommendationRangeLabel(Map<String, dynamic> item, double quantityKg) {
  final low = _number(item['range_low_kg'] ?? item['lower_bound_kg']);
  final high = _number(item['range_high_kg'] ?? item['upper_bound_kg']);
  final lower = low ?? roundToHalfKg(quantityKg * 0.75);
  final upper = high ?? roundToHalfKg(quantityKg * 1.25);
  if (!lower.isFinite || !upper.isFinite || lower < 0 || upper < lower) {
    return null;
  }
  return 'Likely range: ${_kgLabel(lower)} to ${_kgLabel(upper)}';
}

String forecastConfidenceLabel(Map<String, dynamic> item) {
  final beatsBaseline = item['beats_baseline'];
  final wape = _number(item['wape_pct']);
  if (beatsBaseline is bool) {
    if (!beatsBaseline) return 'Low confidence';
    if (wape != null && wape <= 25) return 'High confidence';
    return 'Medium confidence';
  }
  final historyDays = (item['history_days'] as num?)?.toInt();
  if (historyDays != null) {
    if (historyDays >= 90) return 'High confidence';
    if (historyDays >= 28) return 'Medium confidence';
    return 'Low confidence';
  }
  final label = item['confidence_label']?.toString().toLowerCase();
  if (label?.contains('high') == true) return 'Medium confidence';
  if (label?.contains('medium') == true) return 'Medium confidence';
  return 'Low confidence';
}

String bundleConfidenceLabel(int baskets) {
  if (baskets < 20) return 'Low confidence';
  if (baskets < 50) return 'Medium confidence';
  return 'High confidence';
}

double? _number(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}

String _kgLabel(double value) =>
    '${value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1)} kg';
