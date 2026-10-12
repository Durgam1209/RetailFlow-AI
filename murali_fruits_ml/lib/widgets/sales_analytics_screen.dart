import '../theme/app_theme.dart';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/sales_summary_model.dart';
import '../utils/currency_formatter.dart';

enum _DateRange { sevenDays, thirtyDays, all }

class _AnalyticsPayload {
  const _AnalyticsPayload({
    required this.summaries,
    required this.itemRevenue,
    required this.hourlySales,
  });

  final List<SalesSummary> summaries;
  final List<Map<String, dynamic>> itemRevenue;
  final List<Map<String, dynamic>> hourlySales;
}

class _AnalyticsView {
  const _AnalyticsView({
    required this.current,
    required this.previous,
    required this.itemRevenue,
    required this.hourlySales,
    required this.periodLabel,
  });

  final List<SalesSummary> current;
  final List<SalesSummary> previous;
  final List<Map<String, dynamic>> itemRevenue;
  final List<Map<String, dynamic>> hourlySales;
  final String periodLabel;

  double get revenue => current.fold(0, (sum, item) => sum + item.totalRevenue);
  int get transactions =>
      current.fold(0, (sum, item) => sum + item.transactionCount);
  double get previousRevenue =>
      previous.fold(0, (sum, item) => sum + item.totalRevenue);
  double get averageBillValue => transactions == 0 ? 0 : revenue / transactions;
}

class SalesAnalyticsScreen extends StatefulWidget {
  const SalesAnalyticsScreen({super.key});

  @override
  State<SalesAnalyticsScreen> createState() => _SalesAnalyticsScreenState();
}

class _SalesAnalyticsScreenState extends State<SalesAnalyticsScreen> {
  static const int _pageSize = 1000;
  late Future<_AnalyticsPayload> _summaryFuture;
  _DateRange _selectedRange = _DateRange.all;

  @override
  void initState() {
    super.initState();
    _summaryFuture = _fetchAnalyticsData();
  }

  Future<_AnalyticsPayload> _fetchAnalyticsData() async {
    late List<dynamic> rows;
    try {
      rows = await _fetchPagedRows(
        table: 'daily_sales_metrics_summary',
        columns: '*',
        orderColumn: 'created_date',
      );
    } catch (_) {
      try {
        rows = await _fetchPagedRows(
          table: 'daily_sales_summary',
          columns: '*',
          orderColumn: 'created_date',
        );
      } catch (_) {
        rows = await _fetchPagedRows(
          table: 'sales_log',
          columns: 'created_date,total_amount,transaction_id',
          orderColumn: 'created_at',
        );
        return _loadExtras(_aggregateSalesRows(rows));
      }
    }
    return _loadExtras(_normalizeRows(rows));
  }

  Future<_AnalyticsPayload> _loadExtras(List<SalesSummary> summaries) async {
    List<Map<String, dynamic>> items = <Map<String, dynamic>>[];
    List<Map<String, dynamic>> hours = <Map<String, dynamic>>[];
    try {
      items = (await _fetchPagedRows(
        table: 'daily_item_revenue_summary',
        columns: '*',
        orderColumn: 'created_date',
      )).map((row) => Map<String, dynamic>.from(row as Map)).toList();
    } catch (_) {
      debugPrint(
        'Item revenue view unavailable; apply sql/sales_analytics_extended_views.sql.',
      );
    }
    try {
      hours = (await _fetchPagedRows(
        table: 'sales_by_hour_summary',
        columns: '*',
        orderColumn: 'created_date',
      )).map((row) => Map<String, dynamic>.from(row as Map)).toList();
    } catch (_) {
      debugPrint(
        'Hourly sales view unavailable; apply sql/sales_analytics_extended_views.sql.',
      );
    }
    return _AnalyticsPayload(
      summaries: summaries,
      itemRevenue: items,
      hourlySales: hours,
    );
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
        averageBillValue: bucket.transactions == 0
            ? 0
            : bucket.revenue / bucket.transactions,
      );
    }).toList()..sort((a, b) => a.date.compareTo(b.date));

    return summaries;
  }

  _AnalyticsView _selectRange(_AnalyticsPayload payload) {
    final source = payload.summaries;
    final lastDate = DateUtils.dateOnly(source.last.date);
    final firstDate = DateUtils.dateOnly(source.first.date);
    final days = switch (_selectedRange) {
      _DateRange.sevenDays => 7,
      _DateRange.thirtyDays => 30,
      _DateRange.all => lastDate.difference(firstDate).inDays + 1,
    };
    final start = _selectedRange == _DateRange.all
        ? firstDate
        : lastDate.subtract(Duration(days: days - 1));
    final previousStart = start.subtract(Duration(days: days));
    List<SalesSummary> calendar(DateTime from) =>
        List<SalesSummary>.generate(days, (index) {
          final day = from.add(Duration(days: index));
          return source.cast<SalesSummary?>().firstWhere(
                (item) => item != null && DateUtils.isSameDay(item.date, day),
                orElse: () => null,
              ) ??
              SalesSummary(
                date: day,
                dayOfWeek: _weekdayLabel(day),
                totalRevenue: 0,
                transactionCount: 0,
              );
        });
    final end = start.add(Duration(days: days - 1));
    bool inCurrentRange(Map<String, dynamic> row) {
      final date = DateTime.tryParse(row['created_date']?.toString() ?? '');
      return date != null && !date.isBefore(start) && !date.isAfter(end);
    }

    final items = payload.itemRevenue.where(inCurrentRange).toList();
    final hours = payload.hourlySales.where(inCurrentRange).toList();
    return _AnalyticsView(
      current: calendar(start),
      previous: calendar(previousStart),
      itemRevenue: items,
      hourlySales: hours,
      periodLabel: switch (_selectedRange) {
        _DateRange.sevenDays => '7 days',
        _DateRange.thirtyDays => '30 days',
        _DateRange.all => 'All time',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RetailPalette.canvas,
      body: RefreshIndicator(
        color: RetailPalette.charcoal,
        onRefresh: () async {
          setState(() {
            _summaryFuture = _fetchAnalyticsData();
          });
          await _summaryFuture;
        },
        child: FutureBuilder<_AnalyticsPayload>(
          future: _summaryFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _AnalyticsLoading();
            }
            if (snapshot.hasError) {
              return _StateMessage(
                icon: Icons.error_outline_rounded,
                title: 'Analytics unavailable',
                message: 'Check your connection and try loading sales again.',
                onRetry: () => setState(() {
                  _summaryFuture = _fetchAnalyticsData();
                }),
              );
            }

            final payload = snapshot.data;
            if (payload == null || payload.summaries.isEmpty) {
              return const _StateMessage(
                icon: Icons.bar_chart_rounded,
                title: 'No sales yet',
                message: 'Finish a few transactions to see daily patterns.',
              );
            }
            final data = _selectRange(payload);

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                  children: <Widget>[
                    _AnalyticsHeader(data: data),
                    const SizedBox(height: 14),
                    SegmentedButton<_DateRange>(
                      segments: const <ButtonSegment<_DateRange>>[
                        ButtonSegment(
                          value: _DateRange.sevenDays,
                          label: Text('7 days'),
                        ),
                        ButtonSegment(
                          value: _DateRange.thirtyDays,
                          label: Text('30 days'),
                        ),
                        ButtonSegment(
                          value: _DateRange.all,
                          label: Text('All'),
                        ),
                      ],
                      selected: <_DateRange>{_selectedRange},
                      onSelectionChanged: (selection) => setState(() {
                        _selectedRange = selection.first;
                      }),
                    ),
                    const SizedBox(height: 14),
                    _SummaryCards(data: data),
                    const SizedBox(height: 18),
                    _ChartPanel(
                      title: 'Daily Revenue',
                      subtitle:
                          'Calendar days include days without recorded sales.',
                      child: _RevenueChart(data: data.current),
                    ),
                    const SizedBox(height: 16),
                    _ChartPanel(
                      title: 'Transactions Per Day',
                      subtitle: 'Shows when customer flow is strongest.',
                      child: _TransactionChart(data: data.current),
                    ),
                    const SizedBox(height: 16),
                    _ChartPanel(
                      title: 'Top 5 Items by Revenue',
                      subtitle: 'Item totals for the selected date range.',
                      child: _TopItems(data: data.itemRevenue),
                    ),
                    const SizedBox(height: 16),
                    _ChartPanel(
                      title: 'Sales by Hour',
                      subtitle: 'Transaction revenue grouped by hour.',
                      child: _HourlySales(data: data.hourlySales),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AnalyticsHeader extends StatelessWidget {
  const _AnalyticsHeader({required this.data});

  final _AnalyticsView data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RetailPalette.deepForest,
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
            '${data.periodLabel}: ${_money(data.revenue)} across ${data.transactions} bills. ${_comparisonText(data.revenue, data.previousRevenue)}',
            style: const TextStyle(
              color: RetailPalette.paleMint,
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

  final _AnalyticsView data;

  @override
  Widget build(BuildContext context) {
    final high = data.current.reduce(
      (a, b) => a.totalRevenue >= b.totalRevenue ? a : b,
    );
    final low = data.current.reduce(
      (a, b) => a.totalRevenue <= b.totalRevenue ? a : b,
    );
    final busiest = data.current.reduce(
      (a, b) => a.transactionCount >= b.transactionCount ? a : b,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final useGrid = constraints.maxWidth > 560;
        final cards = <Widget>[
          _MetricCard(
            label: 'Highest Sales',
            value: _dateLabel(high.date),
            detail: _money(high.totalRevenue),
            icon: Icons.trending_up_rounded,
            accent: RetailPalette.toneDFF3E5,
          ),
          _MetricCard(
            label: 'Lowest Sales',
            value: _dateLabel(low.date),
            detail: _money(low.totalRevenue),
            icon: Icons.trending_down_rounded,
            accent: RetailPalette.toneFFE4DE,
          ),
          _MetricCard(
            label: 'Busiest Day',
            value: busiest.dayOfWeek,
            detail: '${busiest.transactionCount} bills',
            icon: Icons.groups_rounded,
            accent: RetailPalette.toneE8F0FF,
          ),
          _MetricCard(
            label: 'Average Bill Value',
            value: _money(data.averageBillValue),
            detail: '${data.transactions} bills',
            icon: Icons.receipt_long_rounded,
            accent: RetailPalette.toneFFF0C7,
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
        border: Border.all(color: RetailPalette.border),
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
            child: Icon(icon, color: RetailPalette.charcoal),
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
                    color: RetailPalette.subtleText,
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
                    color: RetailPalette.bodyText,
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
        border: Border.all(color: RetailPalette.border),
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
              color: RetailPalette.mutedText,
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

    final maxY = highest <= 0 ? 100.0 : (highest * 1.4).clamp(100.0, 1e12);

    return BarChart(
      BarChartData(
        maxY: maxY,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: _titlesData(data, currency: true),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => RetailPalette.charcoal,
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
                color: isHigh ? RetailPalette.green : RetailPalette.gold,
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
    final maxY = highest <= 0 ? 5.0 : highest * 1.4;

    return BarChart(
      BarChartData(
        maxY: maxY,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: _titlesData(data),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => RetailPalette.charcoal,
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
                color: isHigh ? RetailPalette.blue : RetailPalette.tone8FB6D9,
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _TopItems extends StatelessWidget {
  const _TopItems({required this.data});

  final List<Map<String, dynamic>> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Apply sql/sales_analytics_extended_views.sql to show item revenue.',
          ),
        ),
      );
    }
    final totals = <String, double>{};
    for (final row in data) {
      final name = row['fruit_name']?.toString() ?? 'Unknown item';
      totals[name] =
          (totals[name] ?? 0) +
          ((row['total_revenue'] as num?)?.toDouble() ?? 0);
    }
    final ranked = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      children: ranked.take(5).map((entry) {
        return ListTile(
          dense: true,
          title: Text(
            entry.key,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          trailing: Text(
            _money(entry.value),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        );
      }).toList(),
    );
  }
}

class _HourlySales extends StatelessWidget {
  const _HourlySales({required this.data});

  final List<Map<String, dynamic>> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Apply sql/sales_analytics_extended_views.sql to show hourly sales.',
          ),
        ),
      );
    }
    final byHour = List<double>.filled(24, 0);
    for (final row in data) {
      final hour = (row['hour_of_day'] as num?)?.toInt();
      if (hour != null && hour >= 0 && hour < 24) {
        byHour[hour] += (row['total_revenue'] as num?)?.toDouble() ?? 0;
      }
    }
    final maximum = byHour.fold<double>(0, math.max);
    return SizedBox(
      height: 190,
      child: BarChart(
        BarChartData(
          maxY: maximum == 0 ? 1 : maximum * 1.35,
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (value, meta) {
                  final hour = value.toInt();
                  if (hour < 0 || hour >= 24 || hour % 6 != 0) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    child: Text('${hour.toString().padLeft(2, '0')}:00'),
                  );
                },
              ),
            ),
          ),
          barGroups: List<BarChartGroupData>.generate(
            24,
            (hour) => BarChartGroupData(
              x: hour,
              barRods: <BarChartRodData>[
                BarChartRodData(
                  toY: byHour[hour],
                  width: 10,
                  color: RetailPalette.gold,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(3),
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

FlTitlesData _titlesData(List<SalesSummary> data, {bool currency = false}) {
  return FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 68,
        getTitlesWidget: (value, meta) => SideTitleWidget(
          meta: meta,
          child: Text(
            currency ? _money(value) : value.toStringAsFixed(0),
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 48,
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
                    color: RetailPalette.charcoal,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  data[index].shortDate,
                  style: const TextStyle(
                    color: RetailPalette.subtleText,
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
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        const SizedBox(height: 120),
        Icon(icon, size: 48, color: RetailPalette.mutedText),
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
            color: RetailPalette.mutedText,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (onRetry != null) ...<Widget>[
          const SizedBox(height: 16),
          Center(
            child: FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ),
        ],
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
  return formatRupees(value);
}

String _dateLabel(DateTime value) =>
    DateFormat('EEE d MMM', 'en_IN').format(value);

String _comparisonText(double current, double previous) {
  if (previous <= 0) return 'No previous-period baseline';
  final change = ((current - previous) / previous) * 100;
  final direction = change >= 0 ? 'up' : 'down';
  return '${change.abs().round()}% $direction vs previous period';
}

class _AnalyticsLoading extends StatelessWidget {
  const _AnalyticsLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: List<Widget>.generate(
        4,
        (index) => Container(
          height: index == 0 ? 120 : 86,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: RetailPalette.skeleton,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
