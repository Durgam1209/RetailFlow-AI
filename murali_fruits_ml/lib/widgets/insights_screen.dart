import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  late Future<Map<String, dynamic>?> _insightsFuture;

  @override
  void initState() {
    super.initState();
    _insightsFuture = fetchLatestInsights();
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
      backgroundColor: const Color(0xFFF7F3EE),
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
                  'Run python ml_pipeline/main.py to create the first AI report.',
            );
          }

          final data = snapshot.data!;
          final bundles = _decodeList(data['suggested_bundles']);
          final forecasts = _decodeList(data['stock_advice']);
          final festivalAdvice = _decodeMap(data['festival_advice']);
          final placementPlan = _buildPlacementPlan(
            forecasts: forecasts,
            bundles: bundles,
            festivalAdvice: festivalAdvice,
          );
          final summary =
              data['forecast_summary'] as String? ?? 'Demand is steady.';

          return RefreshIndicator(
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
                  subtitle: 'Revenue first, then the exact fruits to prepare.',
                ),
                const SizedBox(height: 10),
                _ForecastList(forecasts: forecasts),
                const SizedBox(height: 20),
                const _SectionHeader(
                  title: 'Shop Placement Plan',
                  subtitle:
                      'Your painted layout, with fruits placed where tomorrow\'s selling plan fits best.',
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
                _BundleList(bundles: bundles),
              ],
            ),
          );
        },
      ),
    );
  }

  List<dynamic> _decodeList(dynamic value) {
    try {
      if (value is String && value.trim().isNotEmpty) {
        final decoded = jsonDecode(value);
        return decoded is List ? decoded : <dynamic>[];
      }
      if (value is List) {
        return value;
      }
    } catch (_) {
      return <dynamic>[];
    }
    return <dynamic>[];
  }

  Map<String, dynamic> _decodeMap(dynamic value) {
    try {
      if (value is String && value.trim().isNotEmpty) {
        final decoded = jsonDecode(value);
        return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      }
      if (value is Map<String, dynamic>) {
        return value;
      }
      if (value is Map) {
        return Map<String, dynamic>.from(value);
      }
    } catch (_) {
      return <String, dynamic>{};
    }
    return <String, dynamic>{};
  }

  bool _isFestivalAdviceActive(Map<String, dynamic> advice) {
    if (advice.isEmpty) {
      return false;
    }
    return advice['is_active'] != false;
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF113D2B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD166),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.auto_graph_rounded,
                  color: Colors.black,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'AI Shop Insights',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            summary,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _MetricPill(
                label: 'Daily revenue',
                value: _formatCurrency(averageRevenue),
              ),
              _MetricPill(
                label: 'Peak day',
                value: _field(peak, 'display_date')?.toString() ?? 'Pending',
              ),
              _MetricPill(label: 'Top stock focus', value: topFruit),
            ],
          ),
          if (updatedAt != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              'Updated ${_formatTimestamp(updatedAt)}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
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
        color: const Color(0xFFFFF0BF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2E2722), width: 1.5),
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
                  color: const Color(0xFF2E2722),
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
                        color: Color(0xFF9A5A00),
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
              color: Color(0xFF2E2722),
              fontSize: 15,
              fontWeight: FontWeight.w900,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            merchandising,
            style: const TextStyle(
              color: Color(0xFF5E534B),
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
                      color: Color(0xFF2E2722),
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
              color: Color(0xFF8B8179),
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
            color: Color(0xFF6A5F57),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
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
        final topFruits = _asDynamicList(_field(forecast, 'top_fruits'));
        final confidence =
            _field(forecast, 'confidence_label')?.toString() ?? 'Learning';

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFFE1D8CE)),
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
                    color: const Color(0xFFE4F5DD),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.inventory_2_rounded,
                    color: Color(0xFF2E7D32),
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
                          color: Color(0xFF5E534B),
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                      if (stockLabel != null) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(
                          stockLabel,
                          style: const TextStyle(
                            color: Color(0xFF8B8179),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                      if (eventAdjustment != null) ...<Widget>[
                        const SizedBox(height: 8),
                        _EventNote(label: eventAdjustment),
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

  final Map<String, List<String>> plan;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE1D8CE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'Layout image active',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
              OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.image_outlined, size: 16),
                label: const Text(
                  'Swap photo later',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'This board now uses your layout image. Later, we can replace it with a real shop photo and keep the same placement zones.',
            style: TextStyle(
              color: Color(0xFF6A5F57),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: 1402 / 1120,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      Image.asset(
                        'assets/images/shop_layout.png',
                        fit: BoxFit.cover,
                      ),
                      _ZoneOverlay(
                        left: 0.25,
                        top: 0.13,
                        width: 0.20,
                        title: 'Elevated L2',
                        fruits: plan['inside_upper_two'] ?? const <String>[],
                      ),
                      _ZoneOverlay(
                        left: 0.28,
                        top: 0.29,
                        width: 0.20,
                        title: 'Elevated L1',
                        fruits: plan['inside_upper_one'] ?? const <String>[],
                      ),
                      _ZoneOverlay(
                        left: 0.52,
                        top: 0.42,
                        width: 0.16,
                        title: 'Counter',
                        fruits: plan['inside_counter'] ?? const <String>[],
                      ),
                      _ZoneOverlay(
                        left: 0.18,
                        top: 0.58,
                        width: 0.22,
                        title: 'Table 2',
                        fruits: plan['outside_table_two'] ?? const <String>[],
                      ),
                      _ZoneOverlay(
                        left: 0.48,
                        top: 0.70,
                        width: 0.11,
                        title: 'Quick flow',
                        fruits: plan['outside_quick_flow'] ?? const <String>[],
                      ),
                      _ZoneOverlay(
                        left: 0.60,
                        top: 0.66,
                        width: 0.18,
                        title: 'Table 1',
                        fruits: plan['outside_table_one'] ?? const <String>[],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const <Widget>[
              _LegendChip(
                label: 'Festival priority',
                icon: Icons.priority_high_rounded,
                tint: Color(0xFFFFF0BF),
              ),
              _LegendChip(
                label: 'Fast-move placement',
                icon: Icons.flash_on_rounded,
                tint: Color(0xFFEAF5E8),
              ),
              _LegendChip(
                label: 'Bundle placement',
                icon: Icons.link_rounded,
                tint: Color(0xFFFFE7BA),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ZoneOverlay extends StatelessWidget {
  const _ZoneOverlay({
    required this.left,
    required this.top,
    required this.width,
    required this.title,
    required this.fruits,
  });

  final double left;
  final double top;
  final double width;
  final String title;
  final List<String> fruits;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: <Widget>[
              Positioned(
                left: constraints.maxWidth * left,
                top: constraints.maxHeight * top,
                width: constraints.maxWidth * width,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF2E2722),
                      width: 1,
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (fruits.isEmpty)
                        const Text(
                          'No suggestion',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF8B8179),
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: fruits.take(3).map((fruit) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '${_fruitEmoji(fruit)} $fruit',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({
    required this.label,
    required this.icon,
    required this.tint,
  });

  final String label;
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 15, color: const Color(0xFF2E2722)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
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
    return Column(
      children: fruits.map((fruit) {
        final name = _field(fruit, 'fruit_name')?.toString() ?? 'Fruit';
        final stock = _field(fruit, 'stock_label')?.toString() ?? name;
        final revenue = _field(fruit, 'revenue_label')?.toString() ?? '';
        final isFestivalPick = _field(fruit, 'is_festival_pick') == true;

        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: isFestivalPick
                ? const Color(0xFFFFF0BF)
                : const Color(0xFFF8F4EE),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                isFestivalPick
                    ? Icons.priority_high_rounded
                    : Icons.inventory_rounded,
                size: 17,
                color: isFestivalPick
                    ? const Color(0xFF9A5A00)
                    : const Color(0xFF5E534B),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  stock,
                  style: const TextStyle(
                    color: Color(0xFF2E2722),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (revenue.isNotEmpty)
                Text(
                  revenue,
                  style: const TextStyle(
                    color: Color(0xFF5E534B),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
        );
      }).toList(),
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
        color: const Color(0xFFFFF0BF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF8B4C00),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _BundleList extends StatelessWidget {
  const _BundleList({required this.bundles});

  final List<dynamic> bundles;

  @override
  Widget build(BuildContext context) {
    if (bundles.isEmpty) {
      return const _EmptyCard(
        icon: Icons.local_offer_outlined,
        title: 'No strong bundles yet',
        message: 'More mixed baskets will unlock pair recommendations.',
      );
    }

    return Column(
      children: bundles.map((bundle) {
        final pair1 = _field(bundle, 'pair_1')?.toString() ?? 'Item';
        final pair2 = _field(bundle, 'pair_2')?.toString() ?? 'Item';
        final title = _field(bundle, 'title')?.toString() ?? '$pair1 + $pair2';
        final confidence = _asInt(_field(bundle, 'confidence_percent'));
        final pairCount = _asInt(_field(bundle, 'pair_count'));
        final strength =
            _field(bundle, 'strength')?.toString() ?? 'Bundle idea';
        final advice =
            _field(bundle, 'advice')?.toString() ??
            'Place these items together to make the basket easier to build.';
        final evidence = pairCount > 0 ? 'Based on $pairCount baskets.' : '';
        final actionLabel = confidence >= 70
            ? 'Display together'
            : 'Test together';

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFFE1D8CE)),
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
                color: const Color(0xFFFFE7BA),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.add_shopping_cart_rounded,
                color: Color(0xFF9A5A00),
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
                    actionLabel,
                    style: const TextStyle(
                      color: Color(0xFF9A5A00),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    advice,
                    style: const TextStyle(
                      color: Color(0xFF5E534B),
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                  if (evidence.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      evidence,
                      style: const TextStyle(
                        color: Color(0xFF8B8179),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            trailing: SizedBox(
              width: 86,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    '$confidence%',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    strength,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Color(0xFF8B8179),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
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
        color: const Color(0xFFF1F6EA),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF2F6F37),
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
        side: const BorderSide(color: Color(0xFFE1D8CE)),
      ),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF6A5F57)),
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
                color: Color(0xFF6A5F57),
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

Map<String, List<String>> _buildPlacementPlan({
  required List<dynamic> forecasts,
  required List<dynamic> bundles,
  required Map<String, dynamic> festivalAdvice,
}) {
  final plan = <String, List<String>>{
    'inside_upper_two': <String>[],
    'inside_upper_one': <String>[],
    'inside_counter': <String>[],
    'outside_table_two': <String>[],
    'outside_quick_flow': <String>[],
    'outside_table_one': <String>[],
  };

  final firstForecast = forecasts.isNotEmpty ? forecasts.first : null;
  final topFruits = _asDynamicList(_field(firstForecast, 'top_fruits'))
      .map((item) => _field(item, 'fruit_name')?.toString())
      .whereType<String>()
      .toList();
  final festivalFruits = _asStringList(festivalAdvice['recommended_fruits']);
  final bundleFruits = bundles
      .take(3)
      .expand(
        (bundle) => <String?>[
          _field(bundle, 'pair_1')?.toString(),
          _field(bundle, 'pair_2')?.toString(),
        ],
      )
      .whereType<String>()
      .toList();

  for (final fruit in festivalFruits) {
    _assignFruitToZone(plan, fruit, festivalPriority: true);
  }
  for (final fruit in topFruits) {
    _assignFruitToZone(plan, fruit);
  }
  for (final fruit in bundleFruits) {
    _assignFruitToZone(plan, fruit, bundlePriority: true);
  }

  return plan;
}

void _assignFruitToZone(
  Map<String, List<String>> plan,
  String fruit, {
  bool festivalPriority = false,
  bool bundlePriority = false,
}) {
  final lower = fruit.toLowerCase();
  String zone;

  if (lower.contains('banana')) {
    zone = 'outside_table_one';
  } else if (lower.contains('apple') || lower.contains('pomegranate')) {
    zone = festivalPriority ? 'outside_table_two' : 'inside_upper_two';
  } else if (lower.contains('orange') || lower.contains('musambi')) {
    zone = 'outside_table_two';
  } else if (lower.contains('grape') || lower.contains('guava')) {
    zone = 'inside_upper_one';
  } else if (lower.contains('watermelon') ||
      lower.contains('papaya') ||
      lower.contains('mango') ||
      lower.contains('season')) {
    zone = 'outside_table_two';
  } else if (bundlePriority) {
    zone = 'outside_quick_flow';
  } else {
    zone = 'inside_counter';
  }

  final bucket = plan[zone]!;
  if (!bucket.contains(fruit) && bucket.length < 4) {
    bucket.add(fruit);
  }
}

String _fruitEmoji(String fruit) {
  final lower = fruit.toLowerCase();
  if (lower.contains('apple') || lower.contains('pomegranate')) {
    return '\u{1F34E}';
  }
  if (lower.contains('banana')) {
    return '\u{1F34C}';
  }
  if (lower.contains('orange') || lower.contains('musambi')) {
    return '\u{1F34A}';
  }
  if (lower.contains('grape')) {
    return '\u{1F347}';
  }
  if (lower.contains('watermelon')) {
    return '\u{1F349}';
  }
  if (lower.contains('papaya') || lower.contains('mango')) {
    return '\u{1F96D}';
  }
  if (lower.contains('guava')) {
    return '\u{1F34D}';
  }
  return '\u{1F34F}';
}

String _formatCurrency(int value) {
  return 'Rs ${value.toString()}';
}

String _formatTimestamp(dynamic value) {
  final parsed = DateTime.tryParse(value.toString());
  if (parsed == null) {
    return value.toString();
  }
  final local = parsed.toLocal();
  final hour = local.hour == 0
      ? 12
      : (local.hour > 12 ? local.hour - 12 : local.hour);
  final minute = local.minute.toString().padLeft(2, '0');
  final meridiem = local.hour >= 12 ? 'PM' : 'AM';
  return '${local.day}/${local.month}/${local.year} $hour:$minute $meridiem';
}
