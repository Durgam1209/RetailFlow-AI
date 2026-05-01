import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/hive_sales_helper.dart';
import 'data/supabase_sync_service.dart';
import 'models/fruit_item.dart';
import 'widgets/fruit_tile.dart';
import 'widgets/insights_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  }
  final salesHelper = HiveSalesHelper();
  await salesHelper.init();
  runApp(
    MuraliFruitsApp(
      salesHelper: salesHelper,
      syncService: SupabaseSyncService(),
    ),
  );
}

class MuraliFruitsApp extends StatelessWidget {
  const MuraliFruitsApp({
    super.key,
    required this.salesHelper,
    required this.syncService,
  });

  final HiveSalesHelper salesHelper;
  final SupabaseSyncService syncService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Murali Fruits',
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF7F3EE),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF2E2722),
          secondary: Color(0xFFCC8A2E),
          surface: Colors.white,
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            height: 1,
            color: Color(0xFF1F1B18),
          ),
          titleLarge: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1F1B18),
          ),
          bodyMedium: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Color(0xFF5E534B),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: Color(0xFF1F1B18),
          elevation: 0,
        ),
      ),
      home: SalesHomePage(salesHelper: salesHelper, syncService: syncService),
    );
  }
}

class SalesHomePage extends StatefulWidget {
  const SalesHomePage({
    super.key,
    required this.salesHelper,
    required this.syncService,
  });

  final HiveSalesHelper salesHelper;
  final SupabaseSyncService syncService;

  @override
  State<SalesHomePage> createState() => _SalesHomePageState();
}

class _SalesHomePageState extends State<SalesHomePage> {
  final TextEditingController _searchController = TextEditingController();
  static const List<FruitItem> _defaultCatalog = <FruitItem>[
    FruitItem(
      id: 'apple_poland',
      name: 'Apple Poland',
      icon: '\u{1F34E}',
      defaultPrice: 220,
      defaultIncrement: 0.5,
    ),
    FruitItem(
      id: 'apple_washington',
      name: 'Apple Washington',
      icon: '\u{1F34E}',
      defaultPrice: 180,
      defaultIncrement: 0.5,
    ),
    FruitItem(
      id: 'banana_big',
      name: 'Banana',
      icon: '\u{1F34C}',
      defaultPrice: 60,
      defaultIncrement: 0.5,
    ),
    FruitItem(
      id: 'banana_yelakki',
      name: 'Yelakki Banana',
      icon: '\u{1F34C}',
      defaultPrice: 90,
      defaultIncrement: 0.5,
    ),
    FruitItem(
      id: 'papaya',
      name: 'Papaya',
      icon: '\u{1F96D}',
      defaultPrice: 50,
      defaultIncrement: 0.5,
    ),
    FruitItem(
      id: 'orange_citrus',
      name: 'Orange Citrus',
      icon: '\u{1F34A}',
      defaultPrice: 120,
      defaultIncrement: 0.5,
    ),
    FruitItem(
      id: 'orange_mandarin',
      name: 'Mandarin Orange',
      icon: '\u{1F34A}',
      defaultPrice: 140,
      defaultIncrement: 0.5,
    ),
    FruitItem(
      id: 'orange_nagpur',
      name: 'Nagpur Orange',
      icon: '\u{1F34A}',
      defaultPrice: 130,
      defaultIncrement: 0.5,
    ),
    FruitItem(
      id: 'musambi',
      name: 'Musambi',
      icon: '\u{1F34B}',
      defaultPrice: 80,
      defaultIncrement: 0.5,
    ),
    FruitItem(
      id: 'grapes_green',
      name: 'Green Grapes',
      icon: '\u{1F347}',
      defaultPrice: 90,
      defaultIncrement: 0.5,
    ),
    FruitItem(
      id: 'grapes_green_seedless',
      name: 'Seedless Green Grapes',
      icon: '\u{1F347}',
      defaultPrice: 110,
      defaultIncrement: 0.5,
    ),
    FruitItem(
      id: 'grapes_black',
      name: 'Black Grapes',
      icon: '\u{1F347}',
      defaultPrice: 100,
      defaultIncrement: 0.5,
    ),
    FruitItem(
      id: 'grapes_black_seedless',
      name: 'Seedless Black Grapes',
      icon: '\u{1F347}',
      defaultPrice: 120,
      defaultIncrement: 0.5,
    ),
    FruitItem(
      id: 'pomegranate',
      name: 'Pomegranate',
      icon: '\u{1F34E}',
      defaultPrice: 160,
      defaultIncrement: 0.5,
    ),
    FruitItem(
      id: 'watermelon',
      name: 'Watermelon',
      icon: '\u{1F349}',
      defaultPrice: 35,
      defaultIncrement: 1,
    ),
    FruitItem(
      id: 'watermelon_kiran',
      name: 'Watermelon Kiran',
      icon: '\u{1F349}',
      defaultPrice: 45,
      defaultIncrement: 1,
    ),
  ];

  late List<FruitItem> _catalog;
  late Map<String, Map<String, dynamic>> _draftItems;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isOnline = false;
  bool _isSyncing = false;
  String? _syncMessage;
  int _pendingSyncCount = 0;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    unawaited(widget.salesHelper.ensureCatalogSeeded(_defaultCatalog));
    _catalog = widget.salesHelper.loadCatalog(_defaultCatalog);
    _draftItems = widget.salesHelper.loadDraftSession(_catalog);
    _pendingSyncCount = widget.salesHelper.getPendingTransactionCount();
    _listenToConnectivity();
  }

  Future<void> _listenToConnectivity() async {
    final connectivity = Connectivity();
    final initialResults = await connectivity.checkConnectivity();
    if (!mounted) {
      return;
    }
    setState(() {
      _isOnline = !initialResults.contains(ConnectivityResult.none);
    });
    if (_isOnline) {
      unawaited(_syncPendingSales());
    }

    _connectivitySubscription = connectivity.onConnectivityChanged.listen((
      results,
    ) {
      final isOnline = !results.contains(ConnectivityResult.none);
      if (!mounted) {
        return;
      }
      setState(() {
        _isOnline = isOnline;
      });
      if (isOnline) {
        unawaited(_syncPendingSales());
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  void _reloadCatalog() {
    _catalog = widget.salesHelper.loadCatalog(_defaultCatalog);
    _draftItems = widget.salesHelper.loadDraftSession(_catalog);
  }

  Future<void> _openManageProducts() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ManageProductsSheet(
        catalog: _catalog,
        onAddProduct: _addProduceItem,
        onDeleteProduct: _deleteProduceItem,
      ),
    );

    if (changed == true && mounted) {
      setState(_reloadCatalog);
    }
  }

  Future<void> _addProduceItem() async {
    final created = await showModalBottomSheet<FruitItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ProduceEditorSheet(
        existingIds: _catalog.map((fruit) => fruit.id).toSet(),
      ),
    );

    if (created == null) {
      return;
    }

    await widget.salesHelper.addCatalogItem(created);
    if (!mounted) {
      return;
    }
    setState(_reloadCatalog);
  }

  Future<void> _deleteProduceItem(FruitItem fruit) async {
    final hasQuantity = _quantityFor(fruit) > 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Remove ${fruit.name}?'),
          content: Text(
            hasQuantity
                ? 'This will also remove it from the current draft sale.'
                : 'It will disappear from the counter, but past sales stay saved.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB3261E),
                foregroundColor: Colors.white,
              ),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await widget.salesHelper.deleteCatalogItem(fruit.id);
    if (!mounted) {
      return;
    }
    setState(_reloadCatalog);
  }

  Future<void> _removeDraftLine(FruitItem fruit) async {
    await widget.salesHelper.setDraftQuantity(fruit: fruit, quantityKg: 0);
    if (!mounted) {
      return;
    }
    setState(() {
      _draftItems = widget.salesHelper.loadDraftSession(_catalog);
    });
  }

  Future<void> _clearCurrentBill() async {
    await widget.salesHelper.clearDraftSession();
    if (!mounted) {
      return;
    }
    setState(() {
      _draftItems = widget.salesHelper.loadDraftSession(_catalog);
    });
  }

  Future<void> _incrementFruit(FruitItem fruit, double quantity) async {
    HapticFeedback.mediumImpact();
    await widget.salesHelper.upsertDraftLine(
      fruit: fruit,
      quantityDelta: quantity,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _draftItems = widget.salesHelper.loadDraftSession(_catalog);
    });
  }

  Future<void> _decrementFruit(FruitItem fruit) async {
    HapticFeedback.selectionClick();
    await widget.salesHelper.upsertDraftLine(
      fruit: fruit,
      quantityDelta: -fruit.defaultIncrement,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _draftItems = widget.salesHelper.loadDraftSession(_catalog);
    });
  }

  Future<void> _editPrice(FruitItem fruit) async {
    final currentPrice = _priceFor(fruit);
    final updatedPrice = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PriceEditorSheet(
        fruitName: fruit.name,
        currentPrice: currentPrice,
        defaultPrice: fruit.defaultPrice,
      ),
    );

    if (updatedPrice == null) {
      return;
    }

    HapticFeedback.mediumImpact();
    await widget.salesHelper.setDraftPrice(
      fruit: fruit,
      unitPrice: updatedPrice,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _draftItems = widget.salesHelper.loadDraftSession(_catalog);
    });
  }

  Future<void> _editWeight(FruitItem fruit) async {
    final initialQuantityKg = _quantityFor(fruit);
    final updatedWeight = await showModalBottomSheet<_WeightEditResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _WeightEditorSheet(
        fruitName: fruit.name,
        initialQuantityKg: initialQuantityKg,
        initialMetric: _metricFor(fruit),
        defaultIncrement: fruit.defaultIncrement,
      ),
    );

    if (updatedWeight == null) {
      return;
    }

    HapticFeedback.mediumImpact();
    await widget.salesHelper.setDraftQuantity(
      fruit: fruit,
      quantityKg: updatedWeight.quantityKg,
      displayMetric: updatedWeight.displayMetric,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _draftItems = widget.salesHelper.loadDraftSession(_catalog);
    });
  }

  Future<void> _syncPendingSales() async {
    if (_isSyncing || !_isOnline || !widget.syncService.isConfigured) {
      if (mounted) {
        setState(() {
          _pendingSyncCount = widget.salesHelper.getPendingTransactionCount();
        });
      }
      return;
    }

    setState(() {
      _isSyncing = true;
      _syncMessage = null;
      _pendingSyncCount = widget.salesHelper.getPendingTransactionCount();
    });

    final result = await widget.syncService.syncPendingTransactions(
      widget.salesHelper,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isSyncing = false;
      _syncMessage = result.message;
      _pendingSyncCount = widget.salesHelper.getPendingTransactionCount();
    });
  }

  Future<void> _finishTransaction() async {
    final hasItems = _draftItems.values.any(
      (item) => ((item['quantityKg'] as num?)?.toDouble() ?? 0) > 0,
    );
    if (!hasItems) {
      return;
    }

    final transactionId = await widget.salesHelper.finishTransaction(
      _draftItems,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _draftItems = widget.salesHelper.loadDraftSession(_catalog);
      _pendingSyncCount = widget.salesHelper.getPendingTransactionCount();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Transaction saved: $transactionId'),
        behavior: SnackBarBehavior.floating,
      ),
    );

    if (_isOnline) {
      unawaited(_syncPendingSales());
    }
  }

  double _quantityFor(FruitItem fruit) {
    return (_draftItems[fruit.id]?['quantityKg'] as num?)?.toDouble() ?? 0;
  }

  String _metricFor(FruitItem fruit) {
    final metric = (_draftItems[fruit.id]?['displayMetric'] as String?)
        ?.toLowerCase();
    return metric == 'g' ? 'g' : 'kg';
  }

  double _priceFor(FruitItem fruit) {
    return (_draftItems[fruit.id]?['unitPrice'] as num?)?.toDouble() ??
        widget.salesHelper.getLastSoldPrice(fruit);
  }

  double _lineTotalFor(FruitItem fruit) {
    return (_draftItems[fruit.id]?['lineTotal'] as num?)?.toDouble() ??
        (_quantityFor(fruit) * _priceFor(fruit));
  }

  double get _totalAmount {
    return _catalog.fold<double>(0, (sum, fruit) {
      final item = _draftItems[fruit.id];
      return sum + ((item?['lineTotal'] as num?)?.toDouble() ?? 0);
    });
  }

  double get _totalQuantity {
    return _catalog.fold<double>(0, (sum, fruit) {
      return sum + _quantityFor(fruit);
    });
  }

  List<FruitItem> get _draftCatalogItems {
    final items = _catalog.where((fruit) => _quantityFor(fruit) > 0).toList();
    items.sort((a, b) => _lineTotalFor(b).compareTo(_lineTotalFor(a)));
    return items;
  }

  List<FruitItem> get _visibleCatalog {
    if (_searchQuery.trim().isEmpty) {
      return _catalog;
    }

    final query = _searchQuery.trim().toLowerCase();
    return _catalog.where((fruit) {
      return fruit.name.toLowerCase().contains(query);
    }).toList();
  }

  String get _todayLabel {
    final now = DateTime.now();
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${now.day} ${months[now.month - 1]} ${now.year}';
  }

@override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'RetailFlow AI',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
          bottom: const TabBar(
            labelColor: Color(0xFF1F1B18),
            unselectedLabelColor: Color(0xFF6A5F57),
            indicatorColor: Color(0xFF2E2722),
            labelStyle: TextStyle(fontWeight: FontWeight.w800),
            tabs: [
              Tab(icon: Icon(Icons.shopping_cart), text: 'Sales'),
              Tab(icon: Icon(Icons.insights), text: 'AI Insights'),
            ],
          ),
        ),
        body: TabBarView(
          children: [_buildSalesTab(), const InsightsScreen()],
        ),
      ),
    );
  }

Widget _buildSalesTab() {
    final statusColor = _statusColor();
    final statusText = _statusText();

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: <Widget>[
          const _Backdrop(),
          SafeArea(
            child: Column(
              children: <Widget>[
                Expanded(
                  child: RefreshIndicator(
                    color: const Color(0xFF2E2722),
                    backgroundColor: Colors.white,
                    onRefresh: () async {
                      HapticFeedback.mediumImpact();
                      _reloadCatalog();
                      await Future.delayed(const Duration(milliseconds: 300));
                    },
                    child: CustomScrollView(
                      slivers: <Widget>[
                        SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  _HeroHeader(
                                    todayLabel: _todayLabel,
                                    statusColor: statusColor,
                                    statusText: statusText,
                                    isOnline: _isOnline,
                                    syncActionLabel: _syncActionLabel(),
                                    onSyncTap:
                                        widget.syncService.isConfigured &&
                                            _isOnline &&
                                            !_isSyncing
                                        ? _syncPendingSales
                                        : null,
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: _SummaryCard(
                                          label: 'Total Weight',
                                          value:
                                              '${_totalQuantity.toStringAsFixed(1)} kg',
                                          icon: Icons.scale_rounded,
                                          accent: const Color(0xFFFFE1B6),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _SummaryCard(
                                          label: 'Total Amount',
                                          value:
                                              'Rs ${_totalAmount.toStringAsFixed(0)}',
                                          icon: Icons.payments_rounded,
                                          accent: const Color(0xFFFFC6B8),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 18),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.92),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: Colors.black,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: TextField(
                                      controller: _searchController,
                                      onChanged: (value) {
                                        setState(() {
                                          _searchQuery = value;
                                        });
                                      },
                                      decoration: const InputDecoration(
                                        hintText: 'Search produce',
                                        prefixIcon: Icon(Icons.search_rounded),
                                        border: InputBorder.none,
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  Row(
                                    children: <Widget>[
                                      const Expanded(
                                        child: Text(
                                          'Produce Counter',
                                          style: TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: _openManageProducts,
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.black,
                                          side: const BorderSide(
                                            color: Colors.black,
                                            width: 1.5,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 12,
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.tune_rounded,
                                          size: 18,
                                        ),
                                        label: const Text(
                                          'Manage',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  _CurrentBillPanel(
                                    items: _draftCatalogItems,
                                    totalQuantity: _totalQuantity,
                                    totalAmount: _totalAmount,
                                    quantityFor: _quantityFor,
                                    metricFor: _metricFor,
                                    lineTotalFor: _lineTotalFor,
                                    onEditWeight: _editWeight,
                                    onEditPrice: _editPrice,
                                    onRemoveLine: _removeDraftLine,
                                    onClearAll: _draftCatalogItems.isEmpty
                                        ? null
                                        : _clearCurrentBill,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SliverLayoutBuilder(
                            builder: (context, constraints) {
                              final width = constraints.crossAxisExtent;
                              final crossAxisCount = width < 430
                                  ? 1
                                  : width < 900
                                  ? 2
                                  : 3;
                              final childAspectRatio = crossAxisCount == 1
                                  ? 1.1
                                  : crossAxisCount == 2
                                  ? 0.8
                                  : 0.82;

                              return SliverPadding(
                                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                                sliver: SliverGrid(
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: crossAxisCount,
                                        mainAxisSpacing: 16,
                                        crossAxisSpacing: 16,
                                        childAspectRatio: childAspectRatio,
                                      ),
                                  delegate: SliverChildBuilderDelegate((
                                    context,
                                    index,
                                  ) {
                                    final fruit = _visibleCatalog[index];
                                    return FruitTile(
                                      fruit: fruit,
                                      quantityKg: _quantityFor(fruit),
                                      displayMetric: _metricFor(fruit),
                                      unitPrice: _priceFor(fruit),
                                      lineTotal: _lineTotalFor(fruit),
                                      onEditWeight: () => _editWeight(fruit),
                                      onIncrement: () => _incrementFruit(
                                        fruit,
                                        fruit.defaultIncrement,
                                      ),
                                      onDecrement: () => _decrementFruit(fruit),
                                      onEditPrice: () => _editPrice(fruit),
                                    );
                                  }, childCount: _visibleCatalog.length),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: _draftCatalogItems.isEmpty
                          ? null
                          : _finishTransaction,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2E2722),
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(
                          fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        icon: const Icon(Icons.receipt_long, size: 24),
                        label: const Text('Finish Transaction'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          
        ],
      ),
    );
  }
}

extension on _SalesHomePageState {
  Color _statusColor() {
    if (!widget.syncService.isConfigured) {
      return Colors.black54;
    }
    if (_isSyncing) {
      return const Color(0xFFC46005);
    }
    if (!_isOnline) {
      return Colors.black54;
    }
    if (_pendingSyncCount > 0) {
      return const Color(0xFFC46005);
    }
    return const Color(0xFF117A37);
  }

  String _statusText() {
    if (!widget.syncService.isConfigured) {
      return 'Supabase not configured. Sales stay local in Hive.';
    }
    if (_isSyncing) {
      return 'Syncing $_pendingSyncCount sale(s) to Supabase...';
    }
    if (!_isOnline) {
      if (_pendingSyncCount > 0) {
        return 'Offline: $_pendingSyncCount sale(s) waiting to sync.';
      }
      return 'Offline: every tap is saved locally.';
    }
    if (_pendingSyncCount > 0) {
      return 'Online: $_pendingSyncCount sale(s) ready to sync.';
    }
    return _syncMessage ?? 'Online: all sales synced to Supabase.';
  }

  String? _syncActionLabel() {
    if (!widget.syncService.isConfigured) {
      return null;
    }
    if (_isSyncing) {
      return 'Syncing';
    }
    if (!_isOnline) {
      return null;
    }
    if (_pendingSyncCount > 0) {
      return 'Sync Now';
    }
    return 'Synced';
  }
}

class _CurrentBillPanel extends StatelessWidget {
  const _CurrentBillPanel({
    required this.items,
    required this.totalQuantity,
    required this.totalAmount,
    required this.quantityFor,
    required this.metricFor,
    required this.lineTotalFor,
    required this.onEditWeight,
    required this.onEditPrice,
    required this.onRemoveLine,
    required this.onClearAll,
  });

  final List<FruitItem> items;
  final double totalQuantity;
  final double totalAmount;
  final double Function(FruitItem fruit) quantityFor;
  final String Function(FruitItem fruit) metricFor;
  final double Function(FruitItem fruit) lineTotalFor;
  final Future<void> Function(FruitItem fruit) onEditWeight;
  final Future<void> Function(FruitItem fruit) onEditPrice;
  final Future<void> Function(FruitItem fruit) onRemoveLine;
  final Future<void> Function()? onClearAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'Current Bill',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ),
              TextButton(
                onPressed: onClearAll,
                child: const Text(
                  'Clear',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (items.isEmpty)
            const Text(
              'No items added yet. Tap produce below to start the bill.',
              style: TextStyle(
                color: Color(0xFF6A5F57),
                fontWeight: FontWeight.w700,
              ),
            )
          else
            Column(
              children: items.map((fruit) {
                final quantity = quantityFor(fruit);
                final metric = metricFor(fruit);
                final quantityLabel = metric == 'g'
                    ? '${(quantity * 1000).toStringAsFixed(0)} g'
                    : '${quantity.toStringAsFixed(1)} kg';
                return Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F4EE),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: <Widget>[
                      _MiniProduceIcon(
                        icon: fruit.icon,
                        tint: const Color(0xFFFFF1D9),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              fruit.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$quantityLabel • Rs ${lineTotalFor(fruit).toStringAsFixed(0)}',
                              style: const TextStyle(
                                color: Color(0xFF6A5F57),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Edit weight',
                        onPressed: () => onEditWeight(fruit),
                        icon: const Icon(Icons.scale_rounded),
                      ),
                      IconButton(
                        tooltip: 'Edit price',
                        onPressed: () => onEditPrice(fruit),
                        icon: const Icon(Icons.currency_rupee_rounded),
                      ),
                      IconButton(
                        tooltip: 'Remove line',
                        onPressed: () => onRemoveLine(fruit),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: _BillMetric(
                  label: 'Bill weight',
                  value: '${totalQuantity.toStringAsFixed(1)} kg',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _BillMetric(
                  label: 'Bill amount',
                  value: 'Rs ${totalAmount.toStringAsFixed(0)}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BillMetric extends StatelessWidget {
  const _BillMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFF6A5F57),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _ManageProductsSheet extends StatelessWidget {
  const _ManageProductsSheet({
    required this.catalog,
    required this.onAddProduct,
    required this.onDeleteProduct,
  });

  final List<FruitItem> catalog;
  final Future<void> Function() onAddProduct;
  final Future<void> Function(FruitItem fruit) onDeleteProduct;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.86,
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'Manage Products',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    await onAddProduct();
                    if (context.mounted) {
                      Navigator.of(context).pop(true);
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Add new produce here and remove old catalog items away from the live sales screen.',
              style: TextStyle(
                color: Color(0xFF6A5F57),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                itemCount: catalog.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final fruit = catalog[index];
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F4EE),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: <Widget>[
                        _MiniProduceIcon(
                          icon: fruit.icon,
                          tint: const Color(0xFFFFF1D9),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                fruit.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Rs ${fruit.defaultPrice.toStringAsFixed(0)} / kg • ${_formatMetricLabelValue(fruit.defaultIncrement, 'kg')} per tap',
                                style: const TextStyle(
                                  color: Color(0xFF6A5F57),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove product',
                          onPressed: () async {
                            await onDeleteProduct(fruit);
                            if (context.mounted) {
                              Navigator.of(context).pop(true);
                            }
                          },
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[
            Color(0xFFF8F4EE),
            Color(0xFFF5EFE6),
            Color(0xFFFAF8F4),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.7), width: 1),
        ),
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            top: 110,
            left: 24,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0xFFFFFFFF).withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(32),
              ),
            ),
          ),
          Positioned(
            top: 220,
            right: 28,
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: const Color(0xFFFFE8CC).withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(28),
              ),
            ),
          ),
          Positioned(
            bottom: 120,
            left: 40,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFE7F1E3).withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(22),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({
    required this.todayLabel,
    required this.statusColor,
    required this.statusText,
    required this.isOnline,
    required this.syncActionLabel,
    required this.onSyncTap,
  });

  final String todayLabel;
  final Color statusColor;
  final String statusText;
  final bool isOnline;
  final String? syncActionLabel;
  final VoidCallback? onSyncTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE7DED2)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  todayLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFF4EFE8),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.storefront_rounded,
                  size: 24,
                  color: Color(0xFF2E2722),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Murali Fruits',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Counter billing for daily sales, fast item edits, and offline-safe syncing for the shop.',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 16),
          const Row(
            children: <Widget>[
              _MiniProduceIcon(icon: '\u{1F34E}', tint: Color(0xFFFFEEE8)),
              SizedBox(width: 10),
              _MiniProduceIcon(icon: '\u{1F34A}', tint: Color(0xFFFFF1E1)),
              SizedBox(width: 10),
              _MiniProduceIcon(icon: '\u{1F349}', tint: Color(0xFFEAF5E8)),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            constraints: const BoxConstraints(minHeight: 50),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F4EE),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: statusColor.withValues(alpha: 0.18)),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  isOnline ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                  color: statusColor,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    statusText,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (syncActionLabel != null) ...<Widget>[
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 44,
                    child: FilledButton(
                      onPressed: onSyncTap,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2E2722),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      child: Text(
                        syncActionLabel!,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProduceEditorSheet extends StatefulWidget {
  const _ProduceEditorSheet({required this.existingIds});

  final Set<String> existingIds;

  @override
  State<_ProduceEditorSheet> createState() => _ProduceEditorSheetState();
}

class _ProduceEditorSheetState extends State<_ProduceEditorSheet> {
  static const List<String> _iconChoices = <String>[
    '\u{1F34E}',
    '\u{1F34C}',
    '\u{1F34A}',
    '\u{1F347}',
    '\u{1F349}',
    '\u{1F34D}',
    '\u{1F96D}',
    '\u{1F96D}',
    '\u{1F965}',
    '\u{1F352}',
    '\u{1F351}',
    '\u{1F95D}',
  ];
  static const List<double> _increments = <double>[0.25, 0.5, 1, 2];

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  String _selectedIcon = _iconChoices.first;
  double _selectedIncrement = 0.5;
  String? _errorText;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final price = double.tryParse(_priceController.text.trim());

    if (name.isEmpty) {
      setState(() {
        _errorText = 'Enter the item name';
      });
      return;
    }
    if (price == null || price <= 0) {
      setState(() {
        _errorText = 'Enter a valid price per kg';
      });
      return;
    }

    final id = _uniqueProduceId(name, widget.existingIds);
    Navigator.of(context).pop(
      FruitItem(
        id: id,
        name: name,
        icon: _selectedIcon,
        defaultPrice: _roundCurrencyValue(price),
        defaultIncrement: _selectedIncrement,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.black, width: 2),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Add Produce',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Choose an icon, set the name, and add the usual price per kg.',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _iconChoices.map((icon) {
                    final isSelected = icon == _selectedIcon;
                    return InkWell(
                      onTap: () {
                        setState(() {
                          _selectedIcon = icon;
                        });
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 52,
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFFFE2B8)
                              : const Color(0xFFFFF6EA),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? Colors.black
                                : const Color(0xFFE6DDD1),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Text(icon, style: const TextStyle(fontSize: 28)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Item name',
                    hintText: 'Example: Mango Alphonso',
                    errorText: _errorText,
                    filled: true,
                    fillColor: const Color(0xFFFFFCF7),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onChanged: (_) {
                    if (_errorText != null) {
                      setState(() {
                        _errorText = null;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _priceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d{0,5}(\.\d{0,2})?$'),
                    ),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Default price per kg',
                    prefixText: 'Rs ',
                    filled: true,
                    fillColor: const Color(0xFFFFFCF7),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Tap increment',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _increments.map((increment) {
                    final isSelected = increment == _selectedIncrement;
                    return ChoiceChip(
                      label: Text(
                        '${_formatMetricLabelValue(increment, 'kg')} per tap',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      selected: isSelected,
                      side: const BorderSide(color: Colors.black, width: 1.5),
                      selectedColor: Colors.black,
                      backgroundColor: const Color(0xFFFFF6EA),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Colors.black,
                      ),
                      onSelected: (_) {
                        setState(() {
                          _selectedIncrement = increment;
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: FilledButton.icon(
                    onPressed: _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text(
                      'Add Item',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PriceEditorSheet extends StatefulWidget {
  const _PriceEditorSheet({
    required this.fruitName,
    required this.currentPrice,
    required this.defaultPrice,
  });

  final String fruitName;
  final double currentPrice;
  final double defaultPrice;

  @override
  State<_PriceEditorSheet> createState() => _PriceEditorSheetState();
}

class _PriceEditorSheetState extends State<_PriceEditorSheet> {
  late final TextEditingController _controller;
  String? _errorText;

  List<double> get _presets {
    final values = <double>{
      widget.defaultPrice,
      widget.currentPrice,
      widget.currentPrice - 10,
      widget.currentPrice + 10,
    }.where((price) => price > 0).map(_roundCurrencyValue).toList()..sort();
    return values;
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: _formatEditableNumberValue(widget.currentPrice),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = double.tryParse(_controller.text.trim());
    if (parsed == null || parsed <= 0) {
      setState(() {
        _errorText = 'Enter a valid price above zero';
      });
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(_roundCurrencyValue(parsed));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.black, width: 2),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Set ${widget.fruitName} Price',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1D9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.black, width: 1.5),
                      ),
                      child: Text(
                        'Now Rs ${_formatEditableNumberValue(widget.currentPrice)}',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Pick a quick rate or type the exact price per kg.',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _presets.map((price) {
                    final isCurrent =
                        price == _roundCurrencyValue(widget.currentPrice);
                    return SizedBox(
                      height: 54,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(price),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.black, width: 2),
                          foregroundColor: Colors.black,
                          backgroundColor: isCurrent
                              ? const Color(0xFFFFE2B8)
                              : const Color(0xFFFFF6EA),
                        ),
                        child: Text(
                          'Rs ${_formatEditableNumberValue(price)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d{0,5}(\.\d{0,2})?$'),
                    ),
                  ],
                  onChanged: (_) {
                    if (_errorText != null) {
                      setState(() {
                        _errorText = null;
                      });
                    }
                  },
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'Custom price per kg',
                    prefixText: 'Rs ',
                    helperText: 'Example: 120 or 120.50',
                    errorText: _errorText,
                    filled: true,
                    fillColor: const Color(0xFFFFFCF7),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: FilledButton(
                    onPressed: _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: const Text(
                      'Save Price',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WeightEditResult {
  const _WeightEditResult({
    required this.quantityKg,
    required this.displayMetric,
  });

  final double quantityKg;
  final String displayMetric;
}

String _uniqueProduceId(String name, Set<String> existingIds) {
  final base = name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  final normalizedBase = base.isEmpty ? 'custom_item' : 'custom_$base';

  var candidate = normalizedBase;
  var suffix = 2;
  while (existingIds.contains(candidate)) {
    candidate = '${normalizedBase}_$suffix';
    suffix++;
  }
  return candidate;
}

class _WeightEditorSheet extends StatefulWidget {
  const _WeightEditorSheet({
    required this.fruitName,
    required this.initialQuantityKg,
    required this.initialMetric,
    required this.defaultIncrement,
  });

  final String fruitName;
  final double initialQuantityKg;
  final String initialMetric;
  final double defaultIncrement;

  @override
  State<_WeightEditorSheet> createState() => _WeightEditorSheetState();
}

class _WeightEditorSheetState extends State<_WeightEditorSheet> {
  late final TextEditingController _controller;
  late String _selectedMetric;
  String? _errorText;

  List<double> get _presets => _selectedMetric == 'g'
      ? <double>[0, 250, 500, 1000, 2000]
      : <double>[0, widget.defaultIncrement, 1, 2, 5];

  @override
  void initState() {
    super.initState();
    _selectedMetric = widget.initialMetric == 'g' ? 'g' : 'kg';
    _controller = TextEditingController(
      text: _formatMetricInputValue(
        _convertKgToMetricValue(widget.initialQuantityKg, _selectedMetric),
        _selectedMetric,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _switchMetric(String metric) {
    final parsed = double.tryParse(_controller.text.trim());
    final currentKg = parsed == null
        ? widget.initialQuantityKg
        : _convertMetricToKgValue(parsed, _selectedMetric);

    setState(() {
      _selectedMetric = metric;
      _controller.text = _formatMetricInputValue(
        _convertKgToMetricValue(currentKg, _selectedMetric),
        _selectedMetric,
      );
      _errorText = null;
    });
  }

  void _submit() {
    final parsed = double.tryParse(_controller.text.trim());
    if (parsed == null || parsed < 0) {
      setState(() {
        _errorText = 'Enter a valid weight';
      });
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(
      _WeightEditResult(
        quantityKg: _convertMetricToKgValue(parsed, _selectedMetric),
        displayMetric: _selectedMetric,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.black, width: 2),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Set ${widget.fruitName} Weight',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Choose the metric, tap a quick amount, or type the exact weight.',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <String>['kg', 'g'].map((metric) {
                    final isSelected = _selectedMetric == metric;
                    return ChoiceChip(
                      label: Text(
                        metric.toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      selected: isSelected,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Colors.black,
                      ),
                      side: const BorderSide(color: Colors.black, width: 2),
                      backgroundColor: const Color(0xFFFFF6EA),
                      selectedColor: Colors.black,
                      onSelected: (_) => _switchMetric(metric),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _presets.map((weight) {
                    return SizedBox(
                      height: 54,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(
                          _WeightEditResult(
                            quantityKg: weight == 0
                                ? 0
                                : _convertMetricToKgValue(
                                    weight,
                                    _selectedMetric,
                                  ),
                            displayMetric: _selectedMetric,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.black, width: 2),
                          foregroundColor: Colors.black,
                          backgroundColor: const Color(0xFFFFF6EA),
                        ),
                        child: Text(
                          weight == 0
                              ? 'Clear'
                              : _formatMetricLabelValue(
                                  weight,
                                  _selectedMetric,
                                ),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(
                      _selectedMetric == 'g'
                          ? RegExp(r'^\d{0,5}$')
                          : RegExp(r'^\d{0,4}(\.\d{0,2})?$'),
                    ),
                  ],
                  onChanged: (_) {
                    if (_errorText != null) {
                      setState(() {
                        _errorText = null;
                      });
                    }
                  },
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'Exact weight',
                    suffixText: _selectedMetric,
                    errorText: _errorText,
                    filled: true,
                    fillColor: const Color(0xFFFFFCF7),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: FilledButton(
                    onPressed: _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: const Text(
                      'Save Weight',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

double _roundCurrencyValue(double value) {
  return double.parse(value.toStringAsFixed(2));
}

String _formatEditableNumberValue(double value) {
  return value.truncateToDouble() == value
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
}

double _convertKgToMetricValue(double quantityKg, String metric) {
  return metric == 'g' ? quantityKg * 1000 : quantityKg;
}

double _convertMetricToKgValue(double value, String metric) {
  return metric == 'g' ? value / 1000 : value;
}

String _formatMetricInputValue(double value, String metric) {
  return metric == 'g'
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1);
}

String _formatMetricLabelValue(double value, String metric) {
  if (metric == 'g') {
    return '${value.toStringAsFixed(0)} g';
  }
  return '${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1)} kg';
}

class _MiniProduceIcon extends StatelessWidget {
  const _MiniProduceIcon({required this.icon, required this.tint});

  final String icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(icon, style: const TextStyle(fontSize: 28)),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.black),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}
