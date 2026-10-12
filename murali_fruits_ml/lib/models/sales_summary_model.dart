class SalesSummary {
  const SalesSummary({
    required this.date,
    required this.dayOfWeek,
    required this.totalRevenue,
    required this.transactionCount,
    this.averageBillValue = 0,
  });

  final DateTime date;
  final String dayOfWeek;
  final double totalRevenue;
  final int transactionCount;
  final double averageBillValue;

  factory SalesSummary.fromMap(Map<String, dynamic> map) {
    return SalesSummary(
      date: DateTime.parse(map['created_date'].toString()),
      dayOfWeek: map['day_of_week']?.toString() ?? '',
      totalRevenue: (map['total_revenue'] as num?)?.toDouble() ?? 0,
      transactionCount: (map['total_transactions'] as num?)?.toInt() ?? 0,
      averageBillValue: (map['average_bill_value'] as num?)?.toDouble() ?? 0,
    );
  }

  String get shortDate => '${date.day}/${date.month}';
}
