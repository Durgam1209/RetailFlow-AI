import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:murali_fruits_ml/data/hive_sales_helper.dart';
import 'package:murali_fruits_ml/models/fruit_item.dart';

void main() {
  late Directory directory;
  late HiveSalesHelper helper;
  late Box<Map> draftBox;
  late Box<Map> salesBox;
  late Box<Map> priceBox;
  late Box<Map> catalogBox;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('retailflow-hive-test-');
    Hive.init(directory.path);
    draftBox = await Hive.openBox<Map>('draft');
    salesBox = await Hive.openBox<Map>('sales');
    priceBox = await Hive.openBox<Map>('prices');
    catalogBox = await Hive.openBox<Map>('catalog');
    helper = HiveSalesHelper.forTest(
      draftBox: draftBox,
      salesBox: salesBox,
      priceBox: priceBox,
      catalogBox: catalogBox,
    );
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
    'undo removes a pending sale and restores its bill before sync',
    () async {
      const fruit = FruitItem(
        id: 'banana',
        name: 'Banana',
        icon: '🍌',
        defaultPrice: 60,
        defaultIncrement: 0.5,
      );
      final transactionId = await helper.finishTransaction(
        <String, Map<String, dynamic>>{
          fruit.id: <String, dynamic>{
            'fruitId': fruit.id,
            'fruitName': fruit.name,
            'quantityKg': 0.5,
            'unitPrice': 60.0,
            'lineTotal': 30.0,
          },
        },
      );

      expect(helper.getPendingTransactionCount(), 1);
      expect(await helper.undoPendingTransaction(transactionId), isTrue);
      expect(helper.getPendingTransactionCount(), 0);
      expect(
        helper.loadDraftSession(const <FruitItem>[
          fruit,
        ])[fruit.id]?['quantityKg'],
        0.5,
      );
    },
  );

  test('a synced sale can no longer be undone', () async {
    final transactionId = await helper.finishTransaction(
      <String, Map<String, dynamic>>{
        'item': <String, dynamic>{
          'fruitId': 'item',
          'fruitName': 'Item',
          'quantityKg': 1.0,
          'unitPrice': 10.0,
          'lineTotal': 10.0,
        },
      },
    );
    await helper.markTransactionSynced(transactionId);

    expect(await helper.undoPendingTransaction(transactionId), isFalse);
    expect(salesBox.containsKey(transactionId), isTrue);
  });

  test('zero amount cannot be saved', () async {
    await expectLater(
      helper.finishTransaction(<String, Map<String, dynamic>>{
        'item': <String, dynamic>{
          'fruitId': 'item',
          'fruitName': 'Item',
          'quantityKg': 1.0,
          'unitPrice': 0.0,
          'lineTotal': 0.0,
        },
      }),
      throwsArgumentError,
    );
    expect(helper.getPendingTransactionCount(), 0);
  });

  test('bundle dismissals are retained in local Hive storage', () async {
    await helper.dismissInsightBundle('apple|banana');
    expect(helper.loadDismissedInsightBundleKeys(), contains('apple|banana'));
  });

  test(
    'explicitly saved default price updates local catalog settings',
    () async {
      const fruit = FruitItem(
        id: 'apple',
        name: 'Apple',
        icon: '🍎',
        defaultPrice: 100,
        defaultIncrement: 0.5,
      );
      await catalogBox.put(fruit.id, fruit.toMap());

      await helper.setDraftPrice(
        fruit: fruit,
        unitPrice: 125,
        saveAsDefault: true,
      );

      expect(helper.getLastSoldPrice(fruit), 125);
      expect(
        FruitItem.fromMap(
          Map<String, dynamic>.from(catalogBox.get(fruit.id)!),
        ).defaultPrice,
        125,
      );
    },
  );
}
