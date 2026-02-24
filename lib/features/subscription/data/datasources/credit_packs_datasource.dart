import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/credit_pack_model.dart';

abstract class CreditPacksDataSource {
  Future<List<CreditPackModel>> getActivePacks();
}

class CreditPacksDataSourceImpl implements CreditPacksDataSource {
  final SupabaseClient _supabase;

  CreditPacksDataSourceImpl(this._supabase);

  @override
  Future<List<CreditPackModel>> getActivePacks() async {
    final response = await _supabase
        .from('credit_packs')
        .select(
          'id, name, credits, price, is_popular, has_savings, link_payment, sort_order',
        )
        .eq('is_active', true)
        .order('sort_order', ascending: true);

    return (response as List)
        .map((json) => CreditPackModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}
