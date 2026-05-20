class SalesSummary {
  const SalesSummary({
    required this.date,
    required this.dayOfWeek,
    required this.totalRevenue,
    required this.transactionCount,
  });

  final DateTime date;
  final String dayOfWeek;
  final double totalRevenue;
  final int transactionCount;

  factory SalesSummary.fromMap(Map<String, dynamic> map) {
    return SalesSummary(
      date: DateTime.parse(map['created_date'].toString()),
      dayOfWeek: map['day_of_week']?.toString() ?? '',
      totalRevenue: (map['total_revenue'] as num?)?.toDouble() ?? 0,
      transactionCount: (map['total_transactions'] as num?)?.toInt() ?? 0,
    );
  }

  String get shortDate => '${date.day}/${date.month}';
}
