import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/plan_model.dart';

abstract class PlansDataSource {
  Future<List<PlanModel>> getActivePlans();
}

class PlansDataSourceImpl implements PlansDataSource {
  final SupabaseClient _supabase;

  PlansDataSourceImpl(this._supabase);

  @override
  Future<List<PlanModel>> getActivePlans() async {
    final response = await _supabase
        .from('plans')
        .select(
          'id, name, description, price, duration_months, monthly_credits, features, link_payment, is_active',
        )
        .eq('is_active', true)
        .order('price', ascending: true);

    return (response as List)
        .map((json) => PlanModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}

