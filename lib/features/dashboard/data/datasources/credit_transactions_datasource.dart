import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/credit_transaction_model.dart';

abstract class CreditTransactionsDataSource {
  Future<int> getMonthlyUsageTotal(int year, int month);
  Future<List<CreditTransactionModel>> getUsageTransactionsForMonth(
    int year,
    int month, {
    int offset = 0,
    int limit = 15,
  });
}

class CreditTransactionsDataSourceImpl implements CreditTransactionsDataSource {
  final SupabaseClient _supabase;

  CreditTransactionsDataSourceImpl(this._supabase);

  @override
  Future<int> getMonthlyUsageTotal(int year, int month) async {
    final response = await _supabase.rpc(
      'get_monthly_usage_total',
      params: {'p_year': year, 'p_month': month},
    );
    return (response as int?) ?? 0;
  }

  @override
  Future<List<CreditTransactionModel>> getUsageTransactionsForMonth(
    int year,
    int month, {
    int offset = 0,
    int limit = 15,
  }) async {
    final dateStart = DateTime.utc(year, month, 1);
    final dateEnd = month < 12
        ? DateTime.utc(year, month + 1, 1)
        : DateTime.utc(year + 1, 1, 1);
    final isoStart = dateStart.toIso8601String();
    final isoEnd = dateEnd.toIso8601String();

    final response = await _supabase
        .from('credit_transactions')
        .select('id, user_id, type, amount, description, reference_id, created_at')
        .eq('type', 'usage')
        .lt('amount', 0)
        .gte('created_at', isoStart)
        .lt('created_at', isoEnd)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    return (response as List)
        .map((json) => CreditTransactionModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}
