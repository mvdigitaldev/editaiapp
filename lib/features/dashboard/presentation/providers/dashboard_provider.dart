import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/datasources/credit_transactions_datasource.dart';

final creditTransactionsDataSourceProvider =
    Provider<CreditTransactionsDataSource>((ref) {
  return CreditTransactionsDataSourceImpl(Supabase.instance.client);
});

/// Total de créditos gastos no mês atual. Invalidar após criar edição/geração.
final currentMonthUsageTotalProvider = FutureProvider<int>((ref) async {
  final ds = ref.watch(creditTransactionsDataSourceProvider);
  final now = DateTime.now();
  return ds.getMonthlyUsageTotal(now.year, now.month);
});
