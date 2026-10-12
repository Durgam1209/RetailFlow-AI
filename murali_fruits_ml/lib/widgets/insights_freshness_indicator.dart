import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class InsightsFreshnessIndicator extends StatelessWidget {
  const InsightsFreshnessIndicator({
    super.key,
    required this.updatedAt,
    this.now,
  });

  final String updatedAt;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final updated = DateTime.tryParse(updatedAt)?.toLocal();
    final effectiveUpdated = updated ?? (now ?? DateTime.now());
    final age = updated == null
        ? null
        : (now ?? DateTime.now()).difference(updated);
    final veryStale = age != null && age > const Duration(hours: 72);
    final stale = age != null && age > const Duration(hours: 24);
    final color = veryStale
        ? RetailPalette.toneFF8A80
        : stale
        ? RetailPalette.toneFFD180
        : RetailPalette.white;
    final text = stale
        ? 'Insights are ${age.inDays.clamp(1, 999)} days old, advice may be outdated - Updated ${_format(effectiveUpdated)}'
        : 'Updated ${updated == null ? updatedAt : _format(updated)}';

    return Row(
      children: <Widget>[
        Icon(Icons.access_time_rounded, size: 16, color: color),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

String _format(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour == 0
      ? 12
      : (local.hour > 12 ? local.hour - 12 : local.hour);
  final minute = local.minute.toString().padLeft(2, '0');
  final meridiem = local.hour >= 12 ? 'PM' : 'AM';
  return '${local.day}/${local.month}/${local.year} $hour:$minute $meridiem';
}
