import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/hive_sales_helper.dart';
import 'data/supabase_sync_service.dart';
import 'data/weather_service.dart';
import 'config/app_config.dart';
import 'models/fruit_item.dart';
import 'utils/checkout_validation.dart';
import 'widgets/fruit_tile.dart';
import 'widgets/insights_screen.dart';
import 'widgets/sales_analytics_screen.dart';
import 'widgets/weather_panel.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

const double largePriceChangeWarningPercent = 25;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
    const supabasePublishableKey = String.fromEnvironment(
      'SUPABASE_PUBLISHABLE_KEY',
      defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY'),
    );
    if (supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty) {
      await Supabase.initialize(url: supabaseUrl, anonKey: supabasePublishableKey);
    }
  } catch (e) {
    debugPrint('Supabase init error: $e');
  }

  try {
    final salesHelper = HiveSalesHelper();
    await salesHelper.init();

    // Initialize weather service with OpenWeather API key
    const weatherKey = String.fromEnvironment('WEATHER_KEY', defaultValue: '');
    final weatherService = weatherKey.isNotEmpty
        ? WeatherService(
            apiKey: weatherKey,
            cityName: 'Mahadevapura, Bengaluru',
            latitude: 12.9916,
            longitude: 77.6926,
          )
        : null;

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      debugPrint('Firebase init error: $e');
    }

    runApp(
      MuraliFruitsApp(
        salesHelper: salesHelper,
        syncService: SupabaseSyncService(),
        weatherService: weatherService,
      ),
    );
  } catch (e) {
    debugPrint('App initialization error: $e');
    runApp(
      MaterialApp(
        home: Scaffold(body: Center(child: Text('Error: $e'))),
      ),
    );
  }
}

class MuraliFruitsApp extends StatelessWidget {
  const MuraliFruitsApp({
    super.key,
    required this.salesHelper,
    required this.syncService,
    this.weatherService,
  });

  final HiveSalesHelper salesHelper;
  final SupabaseSyncService syncService;
  final WeatherService? weatherService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: shopName,
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
      home: SalesHomePage(
        salesHelper: salesHelper,
        syncService: syncService,
        weatherService: weatherService,
      ),
    );
  }
}

class SalesHomePage extends StatefulWidget {
  const SalesHomePage({
    super.key,
    required this.salesHelper,
    required this.syncService,
    this.weatherService,
  });

  final HiveSalesHelper salesHelper;
  final SupabaseSyncService syncService;
  final WeatherService? weatherService;

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
  String _selectedCategory = 'All';
  WeatherData? _todayWeather;
  WeatherData? _tomorrowWeather;

  static const List<String> _categories = <String>[
    'All',
    'Apples',
    'Citrus',
    'Tropical',
    'Grapes',
    'Melons',
  ];

  static String _categoryForFruit(String id) {
    switch (id) {
      case 'apple_poland':
      case 'apple_washington':
      case 'pomegranate':
        return 'Apples';
      case 'banana_big':
      case 'banana_yelakki':
      case 'papaya':
        return 'Tropical';
      case 'orange_citrus':
      case 'orange_mandarin':
      case 'orange_nagpur':
      case 'musambi':
        return 'Citrus';
      case 'grapes_green':
      case 'grapes_green_seedless':
      case 'grapes_black':
      case 'grapes_black_seedless':
        return 'Grapes';
      case 'watermelon':
      case 'watermelon_kiran':
        return 'Melons';
      default:
        return 'Other';
    }
  }

  List<FruitItem> get _visibleCatalog {
    var items = _catalog;
    if (_selectedCategory != 'All') {
      items = items.where((fruit) => _categoryForFruit(fruit.id) == _selectedCategory).toList();
    }
    if (_searchQuery.trim().isNotEmpty) {
      final query = _searchQuery.trim().toLowerCase();
      items = items.where((fruit) => fruit.name.toLowerCase().contains(query)).toList();
    }
    return items;
  }

  @override
  void initState() {
    super.initState();
    unawaited(widget.salesHelper.ensureCatalogSeeded(_defaultCatalog));
    _catalog = widget.salesHelper.loadCatalog(_defaultCatalog);
    _draftItems = widget.salesHelper.loadDraftSession(_catalog);
    _pendingSyncCount = widget.salesHelper.getPendingTransactionCount();
    _listenToConnectivity();
    _loadWeather();
  }

  Future<void> _loadWeather() async {
    if (widget.weatherService == null) return;

    try {
      final today = await widget.weatherService!.getTodayWeather();
      final tomorrow = await widget.weatherService!.getTomorrowWeather();

      if (mounted) {
        setState(() {
          _todayWeather = today;
          _tomorrowWeather = tomorrow;
        });
      }
    } catch (e) {
      debugPrint('Error loading weather: $e');
    }
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
    final result = await showModalBottomSheet<_PriceEditResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PriceEditorSheet(
        fruitName: fruit.name,
        currentPrice: currentPrice,
        defaultPrice: fruit.defaultPrice,
      ),
    );

    if (result == null) {
      return;
    }

    HapticFeedback.mediumImpact();
    await widget.salesHelper.setDraftPrice(
      fruit: fruit,
      unitPrice: result.price,
      saveAsDefault: result.saveAsDefault,
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

  Future<void> _retryPendingSync() async {
    final results = await Connectivity().checkConnectivity();
    final online = !results.contains(ConnectivityResult.none);
    if (mounted) {
      setState(() {
        _isOnline = online;
        _pendingSyncCount = widget.salesHelper.getPendingTransactionCount();
      });
    }
    if (online) await _syncPendingSales();
  }

  Future<void> _finishTransaction() async {
    final hasItems = _draftItems.values.any(
      (item) => ((item['quantityKg'] as num?)?.toDouble() ?? 0) > 0 &&
          ((item['lineTotal'] as num?)?.toDouble() ?? 0) > 0,
    );
    if (!hasItems) {
      return;
    }

    Map<String, dynamic>? weatherData;
    if (_todayWeather != null || _tomorrowWeather != null) {
      weatherData = <String, dynamic>{
        if (_todayWeather != null)
          'today': _todayWeather!.toMap(label: 'today'),
        if (_tomorrowWeather != null)
          'tomorrow': _tomorrowWeather!.toMap(label: 'tomorrow'),
        if (_tomorrowWeather != null && widget.weatherService != null)
          'tomorrowRecommendedFruits': widget.weatherService!
              .getRecommendedFruits(_tomorrowWeather!),
      };
    }

    final transactionId = await widget.salesHelper.finishTransaction(
      _draftItems,
      weatherData: weatherData,
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
        content: const Text('Sale saved.'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => unawaited(_undoTransaction(transactionId)),
        ),
      ),
    );

    await Future<void>.delayed(const Duration(seconds: 5));
    if (mounted && _isOnline &&
        widget.salesHelper.getPendingTransactions().any(
          (record) => record['transactionId'] == transactionId,
        )) {
      unawaited(_syncPendingSales());
    }
  }

  Future<void> _undoTransaction(String transactionId) async {
    final restored = await widget.salesHelper.undoPendingTransaction(transactionId);
    if (!mounted) return;
    setState(() {
      _draftItems = widget.salesHelper.loadDraftSession(_catalog);
      _pendingSyncCount = widget.salesHelper.getPendingTransactionCount();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(restored ? 'Sale undone. Bill restored.' : 'Sale already synced.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _undoLastItem() async {
    if (_draftCatalogItems.isNotEmpty) {
      await _removeDraftLine(_draftCatalogItems.last);
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
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Image.asset('assets/images/logo.png', height: 40),
              const SizedBox(width: 12),
              const Text(
                'RetailFlow AI',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
              ),
            ],
          ),
          bottom: const TabBar(
            labelColor: Color(0xFF1F1B18),
            unselectedLabelColor: Color(0xFF6A5F57),
            indicatorColor: Color(0xFF2E2722),
            labelStyle: TextStyle(fontWeight: FontWeight.w800),
            tabs: [
              Tab(icon: Icon(Icons.shopping_cart), text: 'Sales'),
              Tab(icon: Icon(Icons.insights), text: 'AI Insights'),
              Tab(icon: Icon(Icons.analytics_rounded), text: 'Analytics'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildSalesTab(),
            const InsightsScreen(),
            const SalesAnalyticsScreen(),
          ],
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
                                          !_isSyncing
                                      ? _retryPendingSync
                                      : null,
                                ),
                                const SizedBox(height: 14),
                                WeatherDisplayPanel(
                                  todayWeather: _todayWeather,
                                  tomorrowWeather: _tomorrowWeather,
                                  weatherService: widget.weatherService,
                                ),
                                const SizedBox(height: 14),
                                const SizedBox(height: 8),
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
                                const SizedBox(height: 12),
                                SizedBox(
                                  height: 40,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: _categories.length,
                                    separatorBuilder: (context, index) => const SizedBox(width: 8),
                                    itemBuilder: (context, index) {
                                      final cat = _categories[index];
                                      final isSelected = cat == _selectedCategory;
                                      return ChoiceChip(
                                        label: Text(cat),
                                        selected: isSelected,
                                        selectedColor: const Color(0xFF0F382C),
                                        backgroundColor: Colors.white.withValues(alpha: 0.9),
                                        labelStyle: TextStyle(
                                          color: isSelected ? Colors.white : const Color(0xFF1F1B18),
                                          fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16),
                                          side: BorderSide(
                                            color: isSelected ? const Color(0xFF0F382C) : const Color(0xFFE5DED3),
                                          ),
                                        ),
                                        showCheckmark: false,
                                        onSelected: (selected) {
                                          if (selected) {
                                            setState(() {
                                              _selectedCategory = cat;
                                            });
                                          }
                                        },
                                      );
                                    },
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
                      onUndoLastItem: _draftCatalogItems.isEmpty
                          ? null
                          : _undoLastItem,
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
                                ? 1.3
                                : 1.1;

                            return SliverPadding(
                              padding: const EdgeInsets.fromLTRB(20, 4, 20, 48),
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
                      onPressed: _draftCatalogItems.isEmpty || _totalAmount <= 0
                          ? null
                          : _finishTransaction,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2E2722),
                        disabledBackgroundColor: const Color(0xFF716860),
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
                      label: Text(
                        'Finish Transaction · Rs ${_totalAmount.toStringAsFixed(2)}',
                      ),
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
    return _syncMessage ?? 'All sales are already synced';
  }

  String? _syncActionLabel() {
    if (!widget.syncService.isConfigured) {
      return null;
    }
    if (_isSyncing) {
      return 'Syncing';
    }
    if (_pendingSyncCount > 0) {
      return 'Retry';
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
    required this.onUndoLastItem,
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
  final Future<void> Function()? onUndoLastItem;

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
              IconButton(
                tooltip: 'Undo last item',
                onPressed: onUndoLastItem,
                icon: const Icon(Icons.undo_rounded),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7DED2)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 8,
        spacing: 10,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFF4EFE8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.storefront_rounded,
                  size: 23,
                  color: Color(0xFF2E2722),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    shopName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    todayLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF5E534B),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                constraints: const BoxConstraints(maxWidth: 250),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F4EE),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: statusColor.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      isOnline ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                      color: statusColor,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        statusText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              if (syncActionLabel != null) ...<Widget>[
                const SizedBox(width: 4),
                TextButton(
                  onPressed: onSyncTap,
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  child: Text(syncActionLabel!),
                ),
              ],
            ],
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

    if (!isValidItemName(name)) {
      setState(() {
        _errorText = 'Item name must be between 1 and 60 characters';
      });
      return;
    }
    if (price == null || !isValidUnitPrice(price)) {
      setState(() {
        _errorText = 'Enter a price above zero and no more than Rs 100,000';
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
                  maxLength: 60,
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
                      RegExp(r'^\d{0,6}(\.\d{0,2})?$'),
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
  late final FocusNode _priceFocusNode;
  String? _errorText;
  bool _saveAsDefault = false;
  bool _largeChangeConfirmed = false;

  double get _usualPrice => widget.defaultPrice > 0
      ? widget.defaultPrice
      : widget.currentPrice;

  double? get _largeChangePercent {
    final value = double.tryParse(_controller.text.trim());
    if (value == null || _usualPrice <= 0) return null;
    final percent = ((value - _usualPrice).abs() / _usualPrice) * 100;
    return percent > largePriceChangeWarningPercent ? percent : null;
  }

  String? get _largeChangeMessage {
    final value = double.tryParse(_controller.text.trim());
    final percent = _largeChangePercent;
    if (value == null || percent == null) return null;
    final direction = value < _usualPrice ? 'below' : 'above';
    return '${percent.round()}% $direction usual price';
  }

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
    _priceFocusNode = FocusNode()
      ..addListener(() {
        if (_priceFocusNode.hasFocus) {
          _controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _controller.text.length,
          );
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    _priceFocusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = double.tryParse(_controller.text.trim());
    if (parsed == null ||
        !parsed.isFinite ||
        parsed <= 0 ||
        parsed > 100000 ||
        !_hasAtMostTwoDecimals(_controller.text.trim())) {
      setState(() {
        _errorText = 'Enter a price above zero and no more than Rs 100,000';
      });
      return;
    }

    if (_largeChangePercent != null && !_largeChangeConfirmed) {
      setState(() {
        _largeChangeConfirmed = true;
      });
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(
      _PriceEditResult(
        price: _roundCurrencyValue(parsed),
        saveAsDefault: _saveAsDefault,
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
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        widget.fruitName,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close price editor',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    label: Text(
                      'Current price · Rs ${_formatEditableNumberValue(widget.currentPrice)}',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    backgroundColor: const Color(0xFFFFF1D9),
                  ),
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
                        onPressed: () {
                          _controller.text = _formatEditableNumberValue(price);
                          setState(() => _largeChangeConfirmed = false);
                        },
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
                  focusNode: _priceFocusNode,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d{0,6}(\.\d{0,2})?$'),
                    ),
                  ],
                  onChanged: (_) {
                    setState(() {
                      _errorText = null;
                      _largeChangeConfirmed = false;
                    });
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
                if (_largeChangeMessage != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(
                    _largeChangeConfirmed
                        ? '${_largeChangeMessage!}. Tap Save again to confirm.'
                        : '${_largeChangeMessage!}. Tap Save once to review, then again to confirm.',
                    style: TextStyle(
                      color: _largeChangeConfirmed
                          ? const Color(0xFF9A5A00)
                          : const Color(0xFF8A3B12),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                RadioGroup<bool>(
                  groupValue: _saveAsDefault,
                  onChanged: (value) {
                    if (value != null) setState(() => _saveAsDefault = value);
                  },
                  child: const Column(
                    children: <Widget>[
                      RadioListTile<bool>(
                        value: false,
                        title: Text('This bill only'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                      RadioListTile<bool>(
                        value: true,
                        title: Text('Save as new default price'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ],
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
                    child: Text(
                      _largeChangeConfirmed ? 'Confirm price' : 'Apply price',
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

class _PriceEditResult {
  const _PriceEditResult({required this.price, required this.saveAsDefault});

  final double price;
  final bool saveAsDefault;
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
    if (parsed == null || !parsed.isFinite || parsed < 0) {
      setState(() {
        _errorText = 'Enter a weight between 0 and 500 kg';
      });
      return;
    }

    final quantityKg = _convertMetricToKgValue(parsed, _selectedMetric);
    if (!isValidCheckoutQuantity(quantityKg)) {
      setState(() {
        _errorText = 'Enter a weight between 0 and 500 kg';
      });
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(
      _WeightEditResult(
        quantityKg: quantityKg,
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
                          ? RegExp(r'^\d{0,6}$')
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

bool _hasAtMostTwoDecimals(String value) {
  final decimalIndex = value.indexOf('.');
  return decimalIndex < 0 || value.length - decimalIndex - 1 <= 2;
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

