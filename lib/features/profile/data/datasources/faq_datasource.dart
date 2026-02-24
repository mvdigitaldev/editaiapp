import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/faq_item_model.dart';

abstract class FaqDataSource {
  Future<List<FaqItemModel>> getActiveFaqs();
}

class FaqDataSourceImpl implements FaqDataSource {
  final SupabaseClient _supabase;

  FaqDataSourceImpl(this._supabase);

  @override
  Future<List<FaqItemModel>> getActiveFaqs() async {
    final response = await _supabase
        .from('faq_items')
        .select('id, question, answer, sort_order')
        .eq('is_active', true)
        .order('sort_order', ascending: true);

    return (response as List)
        .map((json) => FaqItemModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}
