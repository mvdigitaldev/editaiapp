import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/payment_model.dart';

abstract class PaymentsDataSource {
  Future<List<PaymentModel>> getPayments({required int offset, int limit = 10});
}

class PaymentsDataSourceImpl implements PaymentsDataSource {
  final SupabaseClient _supabase;

  PaymentsDataSourceImpl(this._supabase);

  @override
  Future<List<PaymentModel>> getPayments({
    required int offset,
    int limit = 10,
  }) async {
    final response = await _supabase
        .from('payments')
        .select(
          'id, amount, currency, payment_method, payment_status, payment_provider, paid_at, created_at',
        )
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    return (response as List)
        .map((json) => PaymentModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}
