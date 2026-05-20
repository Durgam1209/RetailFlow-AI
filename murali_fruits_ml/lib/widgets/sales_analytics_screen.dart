import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/sales_summary_model.dart';

class SalesAnalyticsScreen extends StatefulWidget {
  const SalesAnalyticsScreen({super.key});

  @override
  State<SalesAnalyticsScreen> createState() => _SalesAnalyticsScreenState();
}

class _SalesAnalyticsScreenState extends State<SalesAnalyticsScreen> {
  static const int _pageSize = 1000;
  late Future<List<SalesSummary>> _summaryFuture;

  @override
  void initState() {
    super.initState();
    _summaryFuture = _fetchAnalyticsData();
  }

  Future<List<SalesSummary>> _fetchAnalyticsData() async {
    try {
      final data = await _fetchPagedRows(
        table: 'daily_sales_summary',
        columns: '*',
        orderColumn: 'created_date',
      );
      return _normalizeRows(data);
    } catch (_) {
      final data = await _fetchPagedRows(
        table: 'sales_log',
        columns: 'created_date,total_amount,transaction_id',
        orderColumn: 'created_at',
      );
      return _aggregateSalesRows(data);
    }
  }

  Future<List<dynamic>> _fetchPagedRows({
    required String table,
    required String columns,
    required String orderColumn,
  }) async {
    final rows = <dynamic>[];
    var start = 0;

    while (true) {
      final page = await Supabase.instance.client
          .from(table)
          .select(columns)
          .order(orderColumn, ascending: false)
          .range(start, start + _pageSize - 1);

      rows.addAll(page);
      if (page.length < _pageSize) {
        break;
      }
      start += _pageSize;
    }

    return rows;
  }

  List<SalesSummary> _normalizeRows(List<dynamic> rows) {
    return rows
        .map(
          (row) => SalesSummary.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList()
        .reversed
        .toList();
  }

  List<SalesSummary> _aggregateSalesRows(List<dynamic> rows) {
    final grouped = <String, _MutableSummary>{};
    for (final row in rows) {
      final record = Map<String, dynamic>.from(row as Map);
      final date = record['created_date']?.toString();
      if (date == null || date.isEmpty) {
        continue;
      }
      final bucket = grouped.putIfAbsent(date, () {
        return _MutableSummary(date: DateTime.parse(date));
      });
      bucket.revenue += (record['total_amount'] as num?)?.toDouble() ?? 0;
      bucket.transactions += 1;
    }

    final summaries = grouped.values.map((bucket) {
      return SalesSummary(
        date: bucket.date,
        dayOfWeek: _weekdayLabel(bucket.date),
        totalRevenue: bucket.revenue,
        transactionCount: bucket.transactions,
      );
    }).toList()..sort((a, b) => a.date.compareTo(b.date));

    return summaries;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F3EE),
      body: RefreshIndicator(
        color: const Color(0xFF2E2722),
        onRefresh: () async {
          setState(() {
            _summaryFuture = _fetchAnalyticsData();
          });
          await _summaryFuture;
        },
        child: FutureBuilder<List<SalesSummary>>(
          future: _summaryFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _StateMessage(
                icon: Icons.error_outline_rounded,
                title: 'Analytics unavailable',
                message: snapshot.error.toString(),
              );
            }

            final data = snapshot.data ?? const <SalesSummary>[];
            if (data.isEmpty) {
              return const _StateMessage(
                icon: Icons.bar_chart_rounded,
                title: 'No sales yet',
                message: 'Finish a few transactions to see daily patterns.',
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
              children: <Widget>[
                _AnalyticsHeader(data: data),
                const SizedBox(height: 14),
                _SummaryCards(data: data),
                const SizedBox(height: 18),
                _ChartPanel(
                  title: 'Daily Revenue',
                  subtitle: 'Tap a bar to see exact revenue and bills.',
                  child: _RevenueChart(data: data),
                ),
                const SizedBox(height: 16),
                _ChartPanel(
                  title: 'Transactions Per Day',
                  subtitle: 'Shows when customer flow is strongest.',
                  child: _TransactionChart(data: data),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AnalyticsHeader extends StatelessWidget {
  const _AnalyticsHeader({required this.data});

  final List<SalesSummary> data;

  @override
  Widget build(BuildContext context) {
    final revenue = data.fold<double>(
      0,
      (sum, item) => sum + item.totalRevenue,
    );
    final transactions = data.fold<int>(
      0,
      (sum, item) => sum + item.transactionCount,
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF123C2C),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Sales Analytics',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'All ${data.length} selling days: ${_money(revenue)} across $transactions transaction${transactions == 1 ? '' : 's'}.',
            style: const TextStyle(
              color: Color(0xFFEAF5EE),
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.data});

  final List<SalesSummary> data;

  @override
  Widget build(BuildContext context) {
    final high = data.reduce(
      (a, b) => a.totalRevenue >= b.totalRevenue ? a : b,
    );
    final low = data.reduce((a, b) => a.totalRevenue <= b.totalRevenue ? a : b);
    final busiest = data.reduce(
      (a, b) => a.transactionCount >= b.transactionCount ? a : b,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final useGrid = constraints.maxWidth > 560;
        final cards = <Widget>[
          _MetricCard(
            label: 'Highest Sales',
            value: high.dayOfWeek,
            detail: _money(high.totalRevenue),
            icon: Icons.trending_up_rounded,
            accent: const Color(0xFFDFF3E5),
          ),
          _MetricCard(
            label: 'Lowest Sales',
            value: low.dayOfWeek,
            detail: _money(low.totalRevenue),
            icon: Icons.trending_down_rounded,
            accent: const Color(0xFFFFE4DE),
          ),
          _MetricCard(
            label: 'Busiest Day',
            value: busiest.dayOfWeek,
            detail: '${busiest.transactionCount} bills',
            icon: Icons.groups_rounded,
            accent: const Color(0xFFE8F0FF),
          ),
        ];

        if (!useGrid) {
          return Column(
            children: cards
                .map(
                  (card) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: card,
                  ),
                )
                .toList(),
          );
        }

        return Row(
          children: cards
              .map(
                (card) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: card,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 112),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE1D8CE)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: const Color(0xFF2E2722)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF8B8179),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  detail,
                  style: const TextStyle(
                    color: Color(0xFF5E534B),
                    fontWeight: FontWeight.w900,
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

class _ChartPanel extends StatelessWidget {
  const _ChartPanel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE1D8CE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF6A5F57),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 260,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: _chartWidth(child), child: child),
            ),
          ),
        ],
      ),
    );
  }

  double _chartWidth(Widget chart) {
    if (chart is _RevenueChart) {
      return math.max(360, chart.data.length * 58).toDouble();
    }
    if (chart is _TransactionChart) {
      return math.max(360, chart.data.length * 58).toDouble();
    }
    return 360;
  }
}

class _RevenueChart extends StatelessWidget {
  const _RevenueChart({required this.data});

  final List<SalesSummary> data;

  @override
  Widget build(BuildContext context) {
if (data.isEmpty) {
      return const Center(
        child: Text(
          'No revenue data',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      );
    }

    final highest = data
        .map((item) => item.totalRevenue)
        .fold<double>(0, math.max);

    final maxY = highest <= 0 ? 100.0 : (highest * 1.25).clamp(100.0, 1e12);

    return BarChart(
      BarChartData(
        maxY: maxY,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: _titlesData(data),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF2E2722),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final x = group.x;
              final safeIndex = (x >= 0 && x < data.length) ? x.toInt() : -1;
              final summary = safeIndex >= 0 ? data[safeIndex] : null;
              return BarTooltipItem(
'${_money(rod.toY)}\n${summary?.transactionCount ?? 0} bills',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              );
            },
          ),
        ),
        barGroups: List.generate(data.length, (index) {
          final item = data[index];
          final isHigh = item.totalRevenue == highest && highest > 0;
          return BarChartGroupData(
            x: index,
            barRods: <BarChartRodData>[
              BarChartRodData(
                toY: item.totalRevenue,
                width: 22,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(5),
                ),
                color: isHigh
                    ? const Color(0xFF2E7D32)
                    : const Color(0xFFCC8A2E),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _TransactionChart extends StatelessWidget {
  const _TransactionChart({required this.data});

  final List<SalesSummary> data;

  @override
  Widget build(BuildContext context) {
    final highest = data
        .map((item) => item.transactionCount)
        .fold<int>(0, math.max);
    final maxY = highest <= 0 ? 5.0 : highest * 1.3;

    return BarChart(
      BarChartData(
        maxY: maxY,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: _titlesData(data),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF2E2722),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                '${rod.toY.toStringAsFixed(0)} bills\n${_money(data[group.x].totalRevenue)}',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              );
            },
          ),
        ),
        barGroups: List.generate(data.length, (index) {
          final item = data[index];
          final isHigh = item.transactionCount == highest && highest > 0;
          return BarChartGroupData(
            x: index,
            barRods: <BarChartRodData>[
              BarChartRodData(
                toY: item.transactionCount.toDouble(),
                width: 22,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(5),
                ),
                color: isHigh
                    ? const Color(0xFF1769AA)
                    : const Color(0xFF8FB6D9),
              ),
            ],
          );
        }),
      ),
    );
  }
}

FlTitlesData _titlesData(List<SalesSummary> data) {
  return FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    leftTitles: const AxisTitles(
      sideTitles: SideTitles(showTitles: true, reservedSize: 46),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 38,
        getTitlesWidget: (value, meta) {
          final index = value.toInt();
          if (index < 0 || index >= data.length || value != index) {
            return const SizedBox.shrink();
          }
          return SideTitleWidget(
            meta: meta,
            child: Column(
              children: <Widget>[
                Text(
                  data[index].dayOfWeek,
                  style: const TextStyle(
                    color: Color(0xFF2E2722),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  data[index].shortDate,
                  style: const TextStyle(
                    color: Color(0xFF8B8179),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        const SizedBox(height: 120),
        Icon(icon, size: 48, color: const Color(0xFF6A5F57)),
        const SizedBox(height: 12),
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
    );
  }
}

class _MutableSummary {
  _MutableSummary({required this.date});

  final DateTime date;
  double revenue = 0;
  int transactions = 0;
}

String _weekdayLabel(DateTime date) {
  const labels = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return labels[date.weekday - 1];
}

String _money(double value) {
  return 'Rs ${value.round()}';
}
