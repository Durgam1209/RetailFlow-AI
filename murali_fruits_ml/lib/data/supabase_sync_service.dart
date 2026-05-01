import 'package:supabase_flutter/supabase_flutter.dart';

import 'hive_sales_helper.dart';

class SyncRunResult {
  const SyncRunResult({
    required this.syncedCount,
    required this.failedCount,
    required this.message,
  });

  final int syncedCount;
  final int failedCount;
  final String message;
}

class SupabaseSyncService {
  static const String _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  bool get isConfigured =>
      _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty;

  Future<SyncRunResult> syncPendingTransactions(
    HiveSalesHelper salesHelper,
  ) async {
    if (!isConfigured) {
      return const SyncRunResult(
        syncedCount: 0,
        failedCount: 0,
        message: 'Supabase is not configured',
      );
    }

    final pendingTransactions = salesHelper.getPendingTransactions();
    if (pendingTransactions.isEmpty) {
      return const SyncRunResult(
        syncedCount: 0,
        failedCount: 0,
        message: 'All sales are already synced',
      );
    }

    final client = Supabase.instance.client;
    var syncedCount = 0;
    var failedCount = 0;

    for (final transaction in pendingTransactions) {
      final transactionId = transaction['transactionId'] as String?;
      if (transactionId == null) {
        failedCount += 1;
        continue;
      }

      try {
        await client.from('sales_log').upsert(
          <String, dynamic>{
            'transaction_id': transactionId,
            'created_at': transaction['createdAt'],
            'created_date': transaction['createdDate'],
            'created_time': transaction['createdTime'],
            'total_amount': transaction['totalAmount'],
            'item_count': transaction['itemCount'] ?? 0,
            'items': transaction['items'],
            'is_synced': false,
          },
          onConflict: 'transaction_id',
        );

        await salesHelper.markTransactionSynced(transactionId);
        syncedCount += 1;
      } catch (error) {
        await salesHelper.markTransactionSyncFailed(
          transactionId,
          error.toString(),
        );
        failedCount += 1;
      }
    }

    if (failedCount == 0) {
      return SyncRunResult(
        syncedCount: syncedCount,
        failedCount: failedCount,
        message: 'Synced $syncedCount sale(s) to Supabase',
      );
    }

    return SyncRunResult(
      syncedCount: syncedCount,
      failedCount: failedCount,
      message:
          'Synced $syncedCount sale(s), failed on $failedCount sale(s)',
    );
  }
}
