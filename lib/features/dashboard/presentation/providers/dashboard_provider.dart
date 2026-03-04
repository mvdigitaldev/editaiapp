import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/utils/app_time_utils.dart';
import '../../data/datasources/credit_transactions_datasource.dart';

final creditTransactionsDataSourceProvider =
    Provider<CreditTransactionsDataSource>((ref) {
  return CreditTransactionsDataSourceImpl(Supabase.instance.client);
});

/// Total de creditos de uso no mes atual (America/Sao_Paulo).
/// Mantido por compatibilidade com o card do dashboard.
final currentMonthUsageTotalProvider = FutureProvider<int>((ref) async {
  final ds = ref.watch(creditTransactionsDataSourceProvider);
  final now = AppTimeUtils.nowBrazil();
  return ds.getMonthlyUsageTotal(now.year, now.month);
});
