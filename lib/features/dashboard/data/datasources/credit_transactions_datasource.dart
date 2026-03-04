import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/utils/app_time_utils.dart';
import '../models/credit_transaction_model.dart';
import '../models/monthly_credit_summary_model.dart';

abstract class CreditTransactionsDataSource {
  Future<MonthlyCreditSummaryModel> getMonthlyCreditSummary(
    int year,
    int month, {
    String timezone = AppTimeUtils.brazilTimezone,
  });

  Future<int> getMonthlyUsageTotal(int year, int month);

  Future<List<CreditTransactionModel>> getTransactionsForMonth(
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
  Future<MonthlyCreditSummaryModel> getMonthlyCreditSummary(
    int year,
    int month, {
    String timezone = AppTimeUtils.brazilTimezone,
  }) async {
    final response = await _supabase.rpc(
      'get_monthly_credit_summary',
      params: {'p_year': year, 'p_month': month, 'p_tz': timezone},
    );

    if (response is List && response.isNotEmpty) {
      final row = response.first as Map<String, dynamic>;
      return MonthlyCreditSummaryModel.fromJson(row);
    }

    if (response is Map<String, dynamic>) {
      return MonthlyCreditSummaryModel.fromJson(response);
    }

    return MonthlyCreditSummaryModel.empty;
  }

  @override
  Future<int> getMonthlyUsageTotal(int year, int month) async {
    final summary = await getMonthlyCreditSummary(year, month);
    return summary.usageOut;
  }

  @override
  Future<List<CreditTransactionModel>> getTransactionsForMonth(
    int year,
    int month, {
    int offset = 0,
    int limit = 15,
  }) async {
    final range = AppTimeUtils.monthRangeBrazilToUtc(year, month);

    final response = await _supabase
        .from('credit_transactions')
        .select(
            'id, user_id, type, amount, description, reference_id, created_at, expires_at')
        .gte('created_at', range.start.toIso8601String())
        .lt('created_at', range.end.toIso8601String())
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    return (response as List)
        .map((json) =>
            CreditTransactionModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}
