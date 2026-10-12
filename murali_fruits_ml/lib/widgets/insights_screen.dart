import '../theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/hive_sales_helper.dart';
import '../utils/currency_formatter.dart';
import '../utils/insight_parser.dart';
import '../utils/insight_recommendations.dart';
import 'insights_freshness_indicator.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key, required this.salesHelper});

  final HiveSalesHelper salesHelper;

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  late Future<Map<String, dynamic>?> _insightsFuture;
  Set<String> _dismissedBundleKeys = <String>{};

  @override
  void initState() {
    super.initState();
    _insightsFuture = fetchLatestInsights();
    _dismissedBundleKeys = widget.salesHelper.loadDismissedInsightBundleKeys();
  }

  Future<void> _dismissBundle(String key) async {
    await widget.salesHelper.dismissInsightBundle(key);
    if (mounted) setState(() => _dismissedBundleKeys.add(key));
  }

  Future<Map<String, dynamic>?> fetchLatestInsights() async {
    try {
      final response = await Supabase.instance.client
          .from('daily_insights')
          .select()
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response != null) {
        debugPrint('Fetched insights: ${response.keys}');
      } else {
        debugPrint('No insights found in database');
      }
      return response;
    } catch (e) {
      debugPrint('Error fetching insights: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RetailPalette.canvas,
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _insightsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _StateMessage(
              icon: Icons.error_outline_rounded,
              color: Colors.red.shade700,
              title: 'Could not load insights',
              message: '${snapshot.error}',
            );
          }
          if (!snapshot.hasData || snapshot.data == null) {
            return _StateMessage(
              icon: Icons.insights_rounded,
              color: Colors.blue.shade700,
              title: 'No insights yet',
              message:
                  'Run the RetailFlow AI workflow in GitHub Actions to create the first AI report.',
            );
          }

          final data = snapshot.data!;
          final schemaVersion = data['schema_version'];
          if (schemaVersion == null) {
            debugPrint(
              'WARNING: daily_insights is missing schema_version; reading it as a legacy record.',
            );
          } else if (schemaVersion != '1.0') {
            debugPrint(
              'WARNING: Unsupported daily_insights schema_version "$schemaVersion".',
            );
          }
          final bundles = parseInsightList(
            data['suggested_bundles'],
            field: 'suggested_bundles',
          );
          final forecasts = parseInsightList(
            data['stock_advice'],
            field: 'stock_advice',
          );
          final festivalAdvice = parseInsightMap(
            data['festival_advice'],
            field: 'festival_advice',
          );
          final weatherAdvice = parseInsightMap(
            data['weather_advice'],
            field: 'weather_advice',
          );
          final activeBundles = bundles
              .where(
                (bundle) => !_dismissedBundleKeys.contains(_bundleKey(bundle)),
              )
              .toList();
          final visibleWeatherAdvice = weatherAdvice.isNotEmpty
              ? weatherAdvice
              : _weatherAdviceFromForecasts(forecasts);
          final placementPlan = _buildPlacementPlan(
            forecasts: forecasts,
            bundles: activeBundles,
            festivalAdvice: festivalAdvice,
          );
          final summary = parseInsightSummary(data['forecast_summary']);
          if (data['created_at'] == null) {
            debugPrint(
              'WARNING: daily_insights is missing created_at; the update time may be blank.',
            );
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: RefreshIndicator(
                onRefresh: () async {
                  setState(() {
                    _insightsFuture = fetchLatestInsights();
                  });
                  await _insightsFuture;
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                  children: <Widget>[
                    _SummaryPanel(
                      summary: summary,
                      forecasts: forecasts,
                      updatedAt: data['created_at'],
                    ),
                    if (_isFestivalAdviceActive(festivalAdvice)) ...<Widget>[
                      const SizedBox(height: 12),
                      _FestivalBanner(advice: festivalAdvice),
                    ],
                    if (visibleWeatherAdvice.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 12),
                      _WeatherAdviceBanner(advice: visibleWeatherAdvice),
                    ],
                    const SizedBox(height: 18),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          setState(() {
                            _insightsFuture = fetchLatestInsights();
                          });
                          await _insightsFuture;
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text(
                          'Refresh insights',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const _SectionHeader(
                      title: '7-Day Stock Plan',
                      subtitle:
                          'Revenue first, then the exact fruits to prepare.',
                    ),
                    const SizedBox(height: 10),
                    _ForecastList(forecasts: forecasts),
                    const SizedBox(height: 20),
                    const _SectionHeader(
                      title: 'Shop Placement Plan',
                      subtitle:
                          'Simple zones based on forecast priorities and basket pairings.',
                    ),
                    const SizedBox(height: 10),
                    _PlacementPlanCard(plan: placementPlan),
                    const SizedBox(height: 20),
                    const _SectionHeader(
                      title: 'Smart Bundles',
                      subtitle:
                          'Use these as display and counter-placement actions.',
                    ),
                    const SizedBox(height: 10),
                    _BundleList(
                      bundles: bundles,
                      dismissedKeys: _dismissedBundleKeys,
                      onDismiss: _dismissBundle,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Map<String, dynamic> _weatherAdviceFromForecasts(List<dynamic> forecasts) {
    for (final forecast in forecasts) {
      final row = forecast is Map<String, dynamic>
          ? forecast
          : forecast is Map
          ? Map<String, dynamic>.from(forecast)
          : null;
      if (row == null || row['weather_adjustment'] == null) {
        continue;
      }
      return <String, dynamic>{
        'condition': row['weather_condition'] ?? 'Weather',
        'min_temperature': row['weather_min_temperature'],
        'max_temperature': row['weather_max_temperature'],
        'recommended_fruits': row['weather_recommended_fruits'] ?? const [],
        'action': row['weather_adjustment'],
      };
    }
    return <String, dynamic>{};
  }

  bool _isFestivalAdviceActive(Map<String, dynamic> advice) {
    if (advice.isEmpty) {
      return false;
    }
    return advice['is_active'] != false &&
        (advice['priority']?.toString().toLowerCase() ?? 'high') == 'high';
  }
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({
    required this.summary,
    required this.forecasts,
    required this.updatedAt,
  });

  final String summary;
  final List<dynamic> forecasts;
  final dynamic updatedAt;

  @override
  Widget build(BuildContext context) {
    final averageRevenue = _averageRevenue(forecasts);
    final peak = _peakForecast(forecasts);
    final topFruit = _topFruitName(peak);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [RetailPalette.forest, RetailPalette.leaf],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: RetailPalette.forest.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: RetailPalette.toneFBBF24,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.auto_graph_rounded,
                  color: RetailPalette.forest,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: RetailPalette.mint,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'PROPHET ML PIPELINE ACTIVE',
                          style: TextStyle(
                            color: RetailPalette.mint,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'AI Shop Intelligence',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            summary,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _MetricPill(
                label: 'Avg Daily Revenue',
                value: formatRupees(averageRevenue),
              ),
              _MetricPill(
                label: 'Peak Revenue Day',
                value: _field(peak, 'display_date')?.toString() ?? 'Pending',
              ),
              _MetricPill(label: 'Top Stock Focus', value: topFruit),
            ],
          ),
          if (updatedAt != null) ...<Widget>[
            const SizedBox(height: 14),
            InsightsFreshnessIndicator(updatedAt: updatedAt.toString()),
          ],
        ],
      ),
    );
  }

  int _averageRevenue(List<dynamic> rows) {
    if (rows.isEmpty) {
      return 0;
    }
    final total = rows.fold<int>(
      0,
      (sum, item) => sum + _asInt(_field(item, 'expected_revenue')),
    );
    return (total / rows.length).round();
  }

  dynamic _peakForecast(List<dynamic> rows) {
    if (rows.isEmpty) {
      return null;
    }
    return rows.reduce((current, next) {
      final currentDemand = _asInt(_field(current, 'expected_revenue'));
      final nextDemand = _asInt(_field(next, 'expected_revenue'));
      return nextDemand > currentDemand ? next : current;
    });
  }

  String _topFruitName(dynamic forecast) {
    final fruits = _asDynamicList(_field(forecast, 'top_fruits'));
    if (fruits.isEmpty) {
      return 'Learning';
    }
    return _field(fruits.first, 'fruit_name')?.toString() ?? 'Learning';
  }
}

class _FestivalBanner extends StatelessWidget {
  const _FestivalBanner({required this.advice});

  final Map<String, dynamic> advice;

  @override
  Widget build(BuildContext context) {
    final title = advice['title']?.toString() ?? 'Festival demand alert';
    final action =
        advice['action']?.toString() ?? 'Stock up on fast-moving fruits today.';
    final merchandising =
        advice['merchandising']?.toString() ??
        'Place priority fruits at the front of the shop.';
    final basis = advice['basis']?.toString() ?? 'Festival signal';
    final fruits = _asStringList(advice['recommended_fruits']);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: RetailPalette.paleAmber,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: RetailPalette.charcoal, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: RetailPalette.charcoal,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.priority_high_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'High Priority',
                      style: TextStyle(
                        color: RetailPalette.amber,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            action,
            style: const TextStyle(
              color: RetailPalette.charcoal,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            merchandising,
            style: const TextStyle(
              color: RetailPalette.bodyText,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          if (fruits.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: fruits.map((fruit) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    fruit,
                    style: const TextStyle(
                      color: RetailPalette.charcoal,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            basis,
            style: const TextStyle(
              color: RetailPalette.subtleText,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: const TextStyle(
            color: RetailPalette.mutedText,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _WeatherAdviceBanner extends StatelessWidget {
  const _WeatherAdviceBanner({required this.advice});

  final Map<String, dynamic> advice;

  @override
  Widget build(BuildContext context) {
    final condition = advice['condition']?.toString() ?? 'Weather';
    final temperature = advice['temperature'];
    final minTemperature = advice['min_temperature'];
    final maxTemperature = advice['max_temperature'];
    final action = advice['action']?.toString() ?? 'Adjust stock for tomorrow.';
    final fruits = _asStringList(advice['recommended_fruits']);
    final temperatureLabel = minTemperature != null && maxTemperature != null
        ? 'Min $minTemperature C / Max $maxTemperature C'
        : temperature == null
        ? ''
        : '$temperature C';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: RetailPalette.toneE8F4FF,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: RetailPalette.toneB8D8F2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.wb_cloudy_rounded, color: RetailPalette.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tomorrow: $condition${temperatureLabel.isEmpty ? '' : ' - $temperatureLabel'}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            action,
            style: const TextStyle(
              color: RetailPalette.slateBlue,
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
          if (fruits.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: fruits.map((fruit) {
                return _StatusChip(label: fruit);
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _ForecastList extends StatelessWidget {
  const _ForecastList({required this.forecasts});

  final List<dynamic> forecasts;

  @override
  Widget build(BuildContext context) {
    if (forecasts.isEmpty) {
      return const _EmptyCard(
        icon: Icons.hourglass_empty_rounded,
        title: 'Forecast pending',
        message: 'The next pipeline run will add daily stock targets.',
      );
    }

    return Column(
      children: forecasts.map((forecast) {
        final date =
            _field(forecast, 'display_date') ??
            _field(forecast, 'date') ??
            'Next day';
        final demandLabel =
            _field(forecast, 'demand_label') ??
            'Expect about ${_asInt(_field(forecast, 'predicted_demand'))} items';
        final action =
            _field(forecast, 'action') ??
            'Keep around ${_asInt(_field(forecast, 'suggested_stock'))} items ready.';
        final stockLabel = _field(forecast, 'stock_label')?.toString();
        final revenueLabel = _field(forecast, 'revenue_label')?.toString();
        final eventAdjustment = _field(
          forecast,
          'event_adjustment',
        )?.toString();
        final weatherAdjustment = _field(
          forecast,
          'weather_adjustment',
        )?.toString();
        final topFruits = _asDynamicList(_field(forecast, 'top_fruits'));
        final confidence = forecastConfidenceLabel(_asMap(forecast));

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: RetailPalette.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: RetailPalette.toneE4F5DD,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.inventory_2_rounded,
                    color: RetailPalette.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              date.toString(),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          _StatusChip(label: confidence),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        revenueLabel ?? demandLabel.toString(),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        action.toString(),
                        style: const TextStyle(
                          color: RetailPalette.bodyText,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                      if (stockLabel != null) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(
                          stockLabel,
                          style: const TextStyle(
                            color: RetailPalette.subtleText,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                      if (eventAdjustment != null) ...<Widget>[
                        const SizedBox(height: 8),
                        _EventNote(label: eventAdjustment),
                      ],
                      if (weatherAdjustment != null) ...<Widget>[
                        const SizedBox(height: 8),
                        _EventNote(label: weatherAdjustment),
                      ],
                      if (topFruits.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 10),
                        _FruitBreakdown(fruits: topFruits),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _PlacementPlanCard extends StatelessWidget {
  const _PlacementPlanCard({required this.plan});

  final Map<String, List<_PlacementSuggestion>> plan;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: RetailPalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _PlacementZone(
            title: 'Front display',
            icon: Icons.storefront_rounded,
            suggestions:
                plan['front_display'] ?? const <_PlacementSuggestion>[],
          ),
          const SizedBox(height: 10),
          _PlacementZone(
            title: 'Quick-flow',
            icon: Icons.flash_on_rounded,
            suggestions: plan['quick_flow'] ?? const <_PlacementSuggestion>[],
          ),
          const SizedBox(height: 10),
          _PlacementZone(
            title: 'Counter area',
            icon: Icons.point_of_sale_rounded,
            suggestions: plan['counter_area'] ?? const <_PlacementSuggestion>[],
          ),
        ],
      ),
    );
  }
}

class _PlacementSuggestion {
  const _PlacementSuggestion(this.name, this.reason);

  final String name;
  final String reason;
}

class _PlacementZone extends StatelessWidget {
  const _PlacementZone({
    required this.title,
    required this.icon,
    required this.suggestions,
  });

  final String title;
  final IconData icon;
  final List<_PlacementSuggestion> suggestions;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: RetailPalette.warmSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: RetailPalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 19),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 6),
          if (suggestions.isEmpty)
            const Text('No placement advice available yet.')
          else
            ...suggestions.map(
              (item) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${item.name} — ${item.reason}'),
              ),
            ),
        ],
      ),
    );
  }
}

class _FruitBreakdown extends StatelessWidget {
  const _FruitBreakdown({required this.fruits});

  final List<dynamic> fruits;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (final fruit in fruits) {
      final item = _asMap(fruit);
      final name = _field(fruit, 'fruit_name')?.toString() ?? 'Fruit';
      final quantity = recommendationQuantityKg(item);
      if (quantity == null) continue;
      final revenue = _field(fruit, 'revenue_label')?.toString() ?? '';
      final isFestivalPick = _field(fruit, 'is_festival_pick') == true;
      final isWeatherPick = _field(fruit, 'is_weather_pick') == true;
      final range = recommendationRangeLabel(item, quantity);
      rows.add(
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: isFestivalPick || isWeatherPick
                ? RetailPalette.paleAmber
                : RetailPalette.warmSurface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                isFestivalPick
                    ? Icons.priority_high_rounded
                    : isWeatherPick
                    ? Icons.wb_cloudy_rounded
                    : Icons.inventory_rounded,
                size: 17,
                color: isFestivalPick || isWeatherPick
                    ? RetailPalette.amber
                    : RetailPalette.bodyText,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Order about ${_kgLabel(quantity)} $name',
                      style: const TextStyle(
                        color: RetailPalette.charcoal,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (range != null)
                      Text(range, style: const TextStyle(fontSize: 12)),
                    Text(
                      forecastConfidenceLabel(item),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (revenue.isNotEmpty)
                Text(
                  revenue,
                  style: const TextStyle(
                    color: RetailPalette.bodyText,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows.isEmpty
          ? const <Widget>[
              Text('No item has reached the 1 kg recommendation minimum.'),
            ]
          : rows,
    );
  }
}

class _EventNote extends StatelessWidget {
  const _EventNote({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: RetailPalette.paleAmber,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: RetailPalette.amberText,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _BundleList extends StatelessWidget {
  const _BundleList({
    required this.bundles,
    required this.dismissedKeys,
    required this.onDismiss,
  });

  final List<dynamic> bundles;
  final Set<String> dismissedKeys;
  final ValueChanged<String> onDismiss;

  @override
  Widget build(BuildContext context) {
    if (bundles.isEmpty) {
      return const _EmptyCard(
        icon: Icons.local_offer_outlined,
        title: 'No strong bundles yet',
        message: 'More mixed baskets will unlock pair recommendations.',
      );
    }

    final visibleBundles = bundles.where((bundle) {
      final key = _bundleKey(bundle);
      return !dismissedKeys.contains(key);
    }).toList();
    if (visibleBundles.isEmpty) {
      return const _EmptyCard(
        icon: Icons.check_circle_outline_rounded,
        title: 'No active bundle suggestions',
        message: 'Dismissed suggestions stay hidden on this device.',
      );
    }
    return Column(
      children: visibleBundles.map((bundle) {
        final pair1 = _field(bundle, 'pair_1')?.toString() ?? 'Item';
        final pair2 = _field(bundle, 'pair_2')?.toString() ?? 'Item';
        final title = _field(bundle, 'title')?.toString() ?? '$pair1 + $pair2';
        final pairCount = _asInt(_field(bundle, 'pair_count'));
        final antecedentCount = _asInt(_field(bundle, 'antecedent_count'));
        final confidenceLabel = bundleConfidenceLabel(pairCount);
        final key = _bundleKey(bundle);
        final evidence = antecedentCount > 0
            ? 'Bought together in $pairCount of $antecedentCount baskets containing $pair1'
            : 'Bought together $pairCount times';

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: RetailPalette.border),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 8,
            ),
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: RetailPalette.toneFFE7BA,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.add_shopping_cart_rounded,
                color: RetailPalette.amber,
              ),
            ),
            title: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    evidence,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text('Based on $pairCount baskets'),
                ],
              ),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _StatusChip(label: confidenceLabel),
                IconButton(
                  tooltip: 'Dismiss bundle suggestion',
                  onPressed: () => onDismiss(key),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: RetailPalette.toneF1F6EA,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: RetailPalette.deepGreen,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: RetailPalette.border),
      ),
      child: ListTile(
        leading: Icon(icon, color: RetailPalette.mutedText),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(message),
      ),
    );
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, color: color, size: 48),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: RetailPalette.mutedText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

dynamic _field(dynamic row, String key) {
  if (row is Map<String, dynamic>) {
    return row[key];
  }
  if (row is Map) {
    return row[key];
  }
  return null;
}

int _asInt(dynamic value) {
  if (value is num) {
    return value.round().clamp(0, 999999);
  }
  if (value is String) {
    return (double.tryParse(value)?.round() ?? 0).clamp(0, 999999);
  }
  return 0;
}

List<String> _asStringList(dynamic value) {
  if (value is List) {
    return value
        .map((item) => item.toString())
        .where((item) => item.trim().isNotEmpty)
        .toList();
  }
  return <String>[];
}

List<dynamic> _asDynamicList(dynamic value) {
  if (value is List) {
    return value;
  }
  return <dynamic>[];
}

Map<String, List<_PlacementSuggestion>> _buildPlacementPlan({
  required List<dynamic> forecasts,
  required List<dynamic> bundles,
  required Map<String, dynamic> festivalAdvice,
}) {
  final plan = <String, List<_PlacementSuggestion>>{
    'front_display': <_PlacementSuggestion>[],
    'quick_flow': <_PlacementSuggestion>[],
    'counter_area': <_PlacementSuggestion>[],
  };

  final firstForecast = forecasts.isNotEmpty ? forecasts.first : null;
  final topRows = _asDynamicList(_field(firstForecast, 'top_fruits'));
  final topFruits = topRows
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .where((item) => recommendationQuantityKg(item) != null)
      .toList();
  final festivalFruits = _asStringList(festivalAdvice['recommended_fruits']);
  for (final fruit in festivalFruits.take(3)) {
    _addPlacement(plan['front_display']!, fruit, 'Festival priority');
  }
  for (final row in topFruits) {
    final fruit = _field(row, 'fruit_name')?.toString();
    if (fruit == null || festivalFruits.contains(fruit)) continue;
    final target = plan['front_display']!.length < 3
        ? plan['front_display']!
        : plan['counter_area']!;
    _addPlacement(target, fruit, 'Forecast priority');
  }
  for (final bundle in bundles.take(3)) {
    final first = _field(bundle, 'pair_1')?.toString();
    final second = _field(bundle, 'pair_2')?.toString();
    if (first != null && second != null) {
      _addPlacement(plan['quick_flow']!, first, 'Pairs with $second');
      _addPlacement(plan['quick_flow']!, second, 'Pairs with $first');
    }
  }

  return plan;
}

void _addPlacement(
  List<_PlacementSuggestion> zone,
  String fruit,
  String reason,
) {
  if (zone.length < 5 && !zone.any((item) => item.name == fruit)) {
    zone.add(_PlacementSuggestion(fruit, reason));
  }
}

String _bundleKey(dynamic bundle) {
  final pair = <String>[
    _field(bundle, 'pair_1')?.toString().trim().toLowerCase() ?? 'item',
    _field(bundle, 'pair_2')?.toString().trim().toLowerCase() ?? 'item',
  ]..sort();
  return Uri.encodeComponent(pair.join('|'));
}

Map<String, dynamic> _asMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

String _kgLabel(double value) =>
    '${value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1)} kg';
