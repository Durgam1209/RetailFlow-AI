import 'dart:convert';

import 'package:flutter/foundation.dart';

List<dynamic> parseInsightList(dynamic value, {required String field}) {
  try {
    if (value is String && value.trim().isNotEmpty) {
      final decoded = jsonDecode(value);
      if (decoded is List) return decoded;
    }
    if (value is List) return value;
  } catch (_) {
    // Fall through to a safe default for malformed or older payloads.
  }
  debugPrint(
    'WARNING: daily_insights.$field is missing or invalid; using an empty list.',
  );
  return <dynamic>[];
}

Map<String, dynamic> parseInsightMap(dynamic value, {required String field}) {
  try {
    if (value is String && value.trim().isNotEmpty) {
      final decoded = jsonDecode(value);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    if (value is Map) return Map<String, dynamic>.from(value);
  } catch (_) {
    // Fall through to an empty map instead of crashing the insights screen.
  }
  debugPrint(
    'WARNING: daily_insights.$field is missing or invalid; using an empty object.',
  );
  return <String, dynamic>{};
}

String parseInsightSummary(dynamic value) {
  if (value is String && value.isNotEmpty) return value;
  debugPrint(
    'WARNING: daily_insights.forecast_summary is missing or invalid; using a fallback.',
  );
  return 'Demand is steady.';
}
