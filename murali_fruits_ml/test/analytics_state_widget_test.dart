import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:murali_fruits_ml/widgets/sales_analytics_screen.dart';

void main() {
  testWidgets('analytics loading state displays card skeletons', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AnalyticsLoadingSkeleton())),
    );

    expect(find.byType(Container), findsNWidgets(4));
  });

  testWidgets('analytics empty state explains there are no sales', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AnalyticsStateMessage(
            icon: Icons.bar_chart_rounded,
            title: 'No sales yet',
            message: 'Finish a few transactions to see daily patterns.',
          ),
        ),
      ),
    );

    expect(find.text('No sales yet'), findsOneWidget);
  });

  testWidgets('analytics error state exposes a working retry button', (
    tester,
  ) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnalyticsStateMessage(
            icon: Icons.error_outline_rounded,
            title: 'Analytics unavailable',
            message: 'Check your connection and try loading sales again.',
            onRetry: () => retried = true,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });
}
