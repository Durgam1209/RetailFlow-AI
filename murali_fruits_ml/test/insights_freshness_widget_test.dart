import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:murali_fruits_ml/theme/app_theme.dart';
import 'package:murali_fruits_ml/widgets/insights_freshness_indicator.dart';

void main() {
  Future<Color?> renderedColor(WidgetTester tester, int hoursOld) async {
    final now = DateTime(2026, 10, 12, 12);
    final updated = now.subtract(Duration(hours: hoursOld));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: RetailPalette.forest,
          body: InsightsFreshnessIndicator(
            updatedAt: updated.toIso8601String(),
            now: now,
          ),
        ),
      ),
    );
    return tester.widget<Text>(find.byType(Text)).style?.color;
  }

  testWidgets('fresh insight time uses the normal light color', (tester) async {
    expect(await renderedColor(tester, 12), RetailPalette.white);
  });

  testWidgets('insights older than one day turn amber', (tester) async {
    expect(await renderedColor(tester, 48), RetailPalette.toneFFD180);
    expect(find.textContaining('advice may be outdated'), findsOneWidget);
  });

  testWidgets('insights older than three days turn red', (tester) async {
    expect(await renderedColor(tester, 96), RetailPalette.toneFF8A80);
  });
}
