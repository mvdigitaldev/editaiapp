import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/legal_document_model.dart';

abstract class LegalDocumentsDataSource {
  Future<LegalDocumentModel> getBySlug(String slug);
}

class LegalDocumentsDataSourceImpl implements LegalDocumentsDataSource {
  final SupabaseClient _supabase;

  LegalDocumentsDataSourceImpl(this._supabase);

  @override
  Future<LegalDocumentModel> getBySlug(String slug) async {
    final response = await _supabase
        .from('legal_documents')
        .select('id, slug, title, content, updated_at')
        .eq('slug', slug)
        .single();

    return LegalDocumentModel.fromJson(response);
  }
}
