import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:murali_fruits_ml/main.dart';
import 'package:murali_fruits_ml/widgets/sync_status_banner.dart';

Future<void> _openEditor(WidgetTester tester, WidgetBuilder builder) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: builder,
              ),
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open editor'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('price editor validates a zero price', (tester) async {
    await _openEditor(
      tester,
      (_) => const PriceEditorSheet(
        fruitName: 'Apple',
        currentPrice: 100,
        defaultPrice: 100,
      ),
    );

    await tester.enterText(find.byType(TextField), '0');
    await tester.tap(find.text('Apply price'));
    await tester.pump();

    expect(
      find.text('Enter a price above zero and no more than Rs 100,000'),
      findsOneWidget,
    );
  });

  testWidgets('large price changes require a second confirmation tap', (
    tester,
  ) async {
    await _openEditor(
      tester,
      (_) => const PriceEditorSheet(
        fruitName: 'Apple',
        currentPrice: 100,
        defaultPrice: 100,
      ),
    );

    await tester.enterText(find.byType(TextField), '130');
    await tester.tap(find.text('Apply price'));
    await tester.pump();
    expect(find.textContaining('30% above usual price'), findsOneWidget);
    expect(find.text('Confirm price'), findsOneWidget);

    await tester.tap(find.text('Confirm price'));
    await tester.pumpAndSettle();
    expect(find.text('Apple'), findsNothing);
  });

  testWidgets('weight editor accepts decimal kilogram entry', (tester) async {
    await _openEditor(
      tester,
      (_) => const WeightEditorSheet(
        fruitName: 'Banana',
        initialQuantityKg: 0.1,
        initialMetric: 'kg',
        defaultIncrement: 0.5,
      ),
    );

    await tester.enterText(find.byType(TextField), '0.3');
    await tester.tap(find.text('Save Weight'));
    await tester.pumpAndSettle();
    expect(find.text('Banana'), findsNothing);
  });

  testWidgets('sync banner shows pending count and invokes retry', (
    tester,
  ) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SyncStatusBanner(
            label: 'Offline: 3 sales waiting to sync.',
            statusColor: Colors.orange,
            isOnline: false,
            actionLabel: 'Retry',
            onRetry: () => retried = true,
          ),
        ),
      ),
    );

    expect(find.text('Offline: 3 sales waiting to sync.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });

  testWidgets('sync banner retains the already-synced message', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SyncStatusBanner(
            label: 'All sales are already synced',
            statusColor: Colors.green,
            isOnline: true,
          ),
        ),
      ),
    );

    expect(find.text('All sales are already synced'), findsOneWidget);
  });
}
