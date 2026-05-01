import 'dart:math';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/fruit_item.dart';

class HiveSalesHelper {
  static const String _draftBoxName = 'draft_transaction_box';
  static const String _salesBoxName = 'sales_log_box';
  static const String _priceBoxName = 'last_price_box';
  static const String _catalogBoxName = 'produce_catalog_box';
  static const String _draftKey = 'active_draft';

  late final Box<Map> _draftBox;
  late final Box<Map> _salesBox;
  late final Box<Map> _priceBox;
  late final Box<Map> _catalogBox;

  Future<void> init() async {
    await Hive.initFlutter();
    _draftBox = await Hive.openBox<Map>(_draftBoxName);
    _salesBox = await Hive.openBox<Map>(_salesBoxName);
    _priceBox = await Hive.openBox<Map>(_priceBoxName);
    _catalogBox = await Hive.openBox<Map>(_catalogBoxName);
  }

  Future<void> ensureCatalogSeeded(List<FruitItem> defaultCatalog) async {
    if (_catalogBox.isEmpty) {
      for (final fruit in defaultCatalog) {
        await _catalogBox.put(fruit.id, fruit.toMap());
      }
    }
  }

  List<FruitItem> loadCatalog(List<FruitItem> defaultCatalog) {
    final catalog =
        _catalogBox.values
            .map(
              (record) => FruitItem.fromMap(Map<String, dynamic>.from(record)),
            )
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    return catalog.isEmpty ? defaultCatalog : catalog;
  }

  Future<void> addCatalogItem(FruitItem fruit) async {
    await _catalogBox.put(fruit.id, fruit.toMap());
  }

  Future<void> deleteCatalogItem(String fruitId) async {
    await _catalogBox.delete(fruitId);

    final draft = _loadMutableDraft();
    final items = Map<String, dynamic>.from(
      draft['items'] as Map? ?? <String, dynamic>{},
    )..remove(fruitId);
    draft['items'] = items;
    draft.addAll(_timestampFields('updated', DateTime.now()));
    await _draftBox.put(_draftKey, draft);
  }

  Map<String, Map<String, dynamic>> loadDraftSession(List<FruitItem> catalog) {
    final rawDraft = _draftBox.get(_draftKey);
    if (rawDraft == null) {
      return <String, Map<String, dynamic>>{};
    }

    final items = Map<String, dynamic>.from(
      (rawDraft['items'] as Map?) ?? <String, dynamic>{},
    );

    final draft = <String, Map<String, dynamic>>{};
    for (final fruit in catalog) {
      final rawItem = items[fruit.id];
      if (rawItem is Map) {
        draft[fruit.id] = Map<String, dynamic>.from(rawItem);
      }
    }
    return draft;
  }

  double getLastSoldPrice(FruitItem fruit) {
    final priceRecord = _priceBox.get(fruit.id);
    if (priceRecord == null) {
      return fruit.defaultPrice;
    }

    final normalized = Map<String, dynamic>.from(priceRecord);
    return _roundCurrency(
      (normalized['price'] as num?)?.toDouble() ?? fruit.defaultPrice,
    );
  }

  Future<void> upsertDraftLine({
    required FruitItem fruit,
    required double quantityDelta,
  }) async {
    final now = DateTime.now();
    final draft = _loadMutableDraft();
    final items = Map<String, dynamic>.from(
      draft['items'] as Map? ?? <String, dynamic>{},
    );
    final existing = Map<String, dynamic>.from(
      items[fruit.id] as Map? ?? <String, dynamic>{},
    );

    final currentQty = (existing['quantityKg'] as num?)?.toDouble() ?? 0;
    final unitPrice = _roundCurrency(
      (existing['unitPrice'] as num?)?.toDouble() ?? getLastSoldPrice(fruit),
    );
    final updatedQty = max(0, currentQty + quantityDelta);
    final lineTotal = _roundCurrency(updatedQty * unitPrice);

    items[fruit.id] = <String, dynamic>{
      'fruitId': fruit.id,
      'fruitName': fruit.name,
      'icon': fruit.icon,
      'quantityKg': updatedQty,
      'displayMetric': existing['displayMetric'] ?? 'kg',
      'unitPrice': unitPrice,
      'lineTotal': lineTotal,
      'createdAt': existing['createdAt'] ?? now.toIso8601String(),
      ..._timestampFields('updated', now),
    };

    draft['items'] = items;
    draft.addAll(_timestampFields('updated', now));
    await _draftBox.put(_draftKey, draft);
  }

  Future<void> setDraftPrice({
    required FruitItem fruit,
    required double unitPrice,
  }) async {
    final now = DateTime.now();
    final draft = _loadMutableDraft();
    final items = Map<String, dynamic>.from(
      draft['items'] as Map? ?? <String, dynamic>{},
    );
    final existing = Map<String, dynamic>.from(
      items[fruit.id] as Map? ?? <String, dynamic>{},
    );
    final quantity = (existing['quantityKg'] as num?)?.toDouble() ?? 0;

    final roundedPrice = _roundCurrency(unitPrice);
    final lineTotal = _roundCurrency(quantity * roundedPrice);

    items[fruit.id] = <String, dynamic>{
      'fruitId': fruit.id,
      'fruitName': fruit.name,
      'icon': fruit.icon,
      'quantityKg': quantity,
      'displayMetric': existing['displayMetric'] ?? 'kg',
      'unitPrice': roundedPrice,
      'lineTotal': lineTotal,
      'createdAt': existing['createdAt'] ?? now.toIso8601String(),
      ..._timestampFields('updated', now),
    };

    draft['items'] = items;
    draft.addAll(_timestampFields('updated', now));
    await _draftBox.put(_draftKey, draft);
    await _priceBox.put(fruit.id, <String, dynamic>{
      'fruitId': fruit.id,
      'fruitName': fruit.name,
      'price': roundedPrice,
      ..._timestampFields('updated', now),
    });
  }

  Future<void> setDraftQuantity({
    required FruitItem fruit,
    required double quantityKg,
    String? displayMetric,
  }) async {
    final now = DateTime.now();
    final draft = _loadMutableDraft();
    final items = Map<String, dynamic>.from(
      draft['items'] as Map? ?? <String, dynamic>{},
    );
    final existing = Map<String, dynamic>.from(
      items[fruit.id] as Map? ?? <String, dynamic>{},
    );
    final normalizedQty = quantityKg < 0 ? 0 : quantityKg;
    final unitPrice = _roundCurrency(
      (existing['unitPrice'] as num?)?.toDouble() ?? getLastSoldPrice(fruit),
    );
    final lineTotal = _roundCurrency(normalizedQty * unitPrice);

    items[fruit.id] = <String, dynamic>{
      'fruitId': fruit.id,
      'fruitName': fruit.name,
      'icon': fruit.icon,
      'quantityKg': normalizedQty,
      'displayMetric': displayMetric ?? existing['displayMetric'] ?? 'kg',
      'unitPrice': unitPrice,
      'lineTotal': lineTotal,
      'createdAt': existing['createdAt'] ?? now.toIso8601String(),
      ..._timestampFields('updated', now),
    };

    draft['items'] = items;
    draft.addAll(_timestampFields('updated', now));
    await _draftBox.put(_draftKey, draft);
  }

  Future<String> finishTransaction(
    Map<String, Map<String, dynamic>> items,
  ) async {
    final transactionId = _generateTransactionId();
    final timestamp = DateTime.now();
    final filteredItems = items.values
        .where((item) => ((item['quantityKg'] as num?)?.toDouble() ?? 0) > 0)
        .map((item) {
          final normalized = Map<String, dynamic>.from(item);
          normalized['unitPrice'] = _roundCurrency(
            (normalized['unitPrice'] as num?)?.toDouble() ?? 0,
          );
          normalized['lineTotal'] = _roundCurrency(
            (normalized['lineTotal'] as num?)?.toDouble() ?? 0,
          );
          normalized.addAll(_timestampFields('sold', timestamp));
          return normalized;
        })
        .toList();

    final totalAmount = filteredItems.fold<double>(
      0,
      (sum, item) => sum + ((item['lineTotal'] as num?)?.toDouble() ?? 0),
    );
    final itemCount = filteredItems.length;

    await _salesBox.put(transactionId, <String, dynamic>{
      'transactionId': transactionId,
      ..._timestampFields('created', timestamp),
      'items': filteredItems,
      'itemCount': itemCount,
      'totalAmount': _roundCurrency(totalAmount),
      'syncStatus': 'pending',
    });

    for (final item in filteredItems) {
      final fruitId = item['fruitId'] as String?;
      final fruitName = item['fruitName'] as String?;
      final unitPrice = (item['unitPrice'] as num?)?.toDouble();
      if (fruitId != null && unitPrice != null) {
        await _priceBox.put(fruitId, <String, dynamic>{
          'fruitId': fruitId,
          'fruitName': fruitName,
          'price': unitPrice,
          ..._timestampFields('updated', timestamp),
        });
      }
    }

    await clearDraftSession();
    return transactionId;
  }

  Future<void> clearDraftSession() async {
    final now = DateTime.now();
    await _draftBox.put(_draftKey, <String, dynamic>{
      'items': <String, dynamic>{},
      ..._timestampFields('updated', now),
    });
  }

  List<Map<String, dynamic>> getPendingTransactions() {
    return _salesBox.values
        .map((record) => Map<String, dynamic>.from(record))
        .where((record) => record['syncStatus'] != 'synced')
        .toList();
  }

  int getPendingTransactionCount() {
    return getPendingTransactions().length;
  }

  Future<void> markTransactionSynced(String transactionId) async {
    final existing = _salesBox.get(transactionId);
    if (existing == null) {
      return;
    }

    final now = DateTime.now();
    final updated = Map<String, dynamic>.from(existing);
    updated['syncStatus'] = 'synced';
    updated.remove('syncError');
    updated.addAll(_timestampFields('synced', now));
    await _salesBox.put(transactionId, updated);
  }

  Future<void> markTransactionSyncFailed(
    String transactionId,
    String error,
  ) async {
    final existing = _salesBox.get(transactionId);
    if (existing == null) {
      return;
    }

    final now = DateTime.now();
    final updated = Map<String, dynamic>.from(existing);
    updated['syncStatus'] = 'failed';
    updated['syncError'] = error;
    updated.addAll(_timestampFields('syncFailed', now));
    await _salesBox.put(transactionId, updated);
  }

  Map<String, dynamic> _loadMutableDraft() {
    final now = DateTime.now();
    final existing = _draftBox.get(_draftKey);
    if (existing == null) {
      return <String, dynamic>{
        'items': <String, dynamic>{},
        ..._timestampFields('updated', now),
      };
    }
    return Map<String, dynamic>.from(existing);
  }

  Map<String, dynamic> _timestampFields(String prefix, DateTime timestamp) {
    final month = timestamp.month.toString().padLeft(2, '0');
    final day = timestamp.day.toString().padLeft(2, '0');
    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final second = timestamp.second.toString().padLeft(2, '0');

    return <String, dynamic>{
      '${prefix}At': timestamp.toIso8601String(),
      '${prefix}Date': '${timestamp.year}-$month-$day',
      '${prefix}Time': '$hour:$minute:$second',
    };
  }

  double _roundCurrency(double value) {
    return double.parse(value.toStringAsFixed(2));
  }

  String _generateTransactionId() {
    final now = DateTime.now();
    final random = Random().nextInt(9000) + 1000;
    final datePart =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final timePart =
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    return 'TXN-$datePart-$timePart-$random';
  }
}
