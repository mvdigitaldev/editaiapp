import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/categoria_model.dart';
import '../models/modelo_model.dart';

abstract class ModelosDataSource {
  Future<List<CategoriaModel>> getCategorias({bool includeInactive = false});

  Future<List<ModeloModel>> getModelosPorCategoria(
    String categoriaId, {
    bool includeInactive = false,
  });

  Future<void> insertCategoria({
    required String nome,
    required String slug,
    int ordem,
    required bool ativo,
    String? coverImageUrl,
  });

  Future<void> updateCategoria(
    String id, {
    required String nome,
    required String slug,
    int ordem,
    required bool ativo,
    String? coverImageUrl,
  });

  Future<void> deleteCategoria(String id);

  Future<void> insertModelo({
    required String nome,
    String? descricao,
    required String categoriaId,
    String? thumbnailUrl,
    required String promptPadrao,
    required bool ativo,
    int ordem,
  });

  Future<void> updateModelo(
    String id, {
    required String nome,
    String? descricao,
    required String categoriaId,
    String? thumbnailUrl,
    required String promptPadrao,
    required bool ativo,
    int ordem,
  });

  Future<void> deleteModelo(String id);
}

class ModelosDataSourceImpl implements ModelosDataSource {
  final SupabaseClient _supabase;

  ModelosDataSourceImpl(this._supabase);

  @override
  Future<List<CategoriaModel>> getCategorias({
    bool includeInactive = false,
  }) async {
    var query = _supabase
        .from('categorias')
        .select('id, nome, slug, ordem, ativo, cover_image_url');
    if (!includeInactive) {
      query = query.eq('ativo', true);
    }
    final response = await query.order('ordem', ascending: true);
    return (response as List)
        .map((json) => CategoriaModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<ModeloModel>> getModelosPorCategoria(
    String categoriaId, {
    bool includeInactive = false,
  }) async {
    var query = _supabase
        .from('modelos')
        .select(
          'id, nome, descricao, categoria_id, thumbnail_url, prompt_padrao, ativo, ordem',
        )
        .eq('categoria_id', categoriaId);
    if (!includeInactive) {
      query = query.eq('ativo', true);
    }
    final response = await query.order('ordem', ascending: true);
    return (response as List)
        .map((json) => ModeloModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> insertCategoria({
    required String nome,
    required String slug,
    int ordem = 0,
    required bool ativo,
    String? coverImageUrl,
  }) async {
    final row = <String, dynamic>{
      'nome': nome,
      'slug': slug,
      'ordem': ordem,
      'ativo': ativo,
    };
    final url = coverImageUrl?.trim();
    if (url != null && url.isNotEmpty) {
      row['cover_image_url'] = url;
    }
    await _supabase.from('categorias').insert(row);
  }

  @override
  Future<void> updateCategoria(
    String id, {
    required String nome,
    required String slug,
    int ordem = 0,
    required bool ativo,
    String? coverImageUrl,
  }) async {
    final row = <String, dynamic>{
      'nome': nome,
      'slug': slug,
      'ordem': ordem,
      'ativo': ativo,
    };
    final url = coverImageUrl?.trim();
    row['cover_image_url'] =
        (url == null || url.isEmpty) ? null : url;
    await _supabase.from('categorias').update(row).eq('id', id);
  }

  @override
  Future<void> deleteCategoria(String id) async {
    await _supabase.from('categorias').delete().eq('id', id);
  }

  @override
  Future<void> insertModelo({
    required String nome,
    String? descricao,
    required String categoriaId,
    String? thumbnailUrl,
    required String promptPadrao,
    required bool ativo,
    int ordem = 0,
  }) async {
    await _supabase.from('modelos').insert({
      'nome': nome,
      'descricao': descricao,
      'categoria_id': categoriaId,
      'thumbnail_url': _nullableUrl(thumbnailUrl),
      'prompt_padrao': promptPadrao,
      'ativo': ativo,
      'ordem': ordem,
    });
  }

  @override
  Future<void> updateModelo(
    String id, {
    required String nome,
    String? descricao,
    required String categoriaId,
    String? thumbnailUrl,
    required String promptPadrao,
    required bool ativo,
    int ordem = 0,
  }) async {
    await _supabase.from('modelos').update({
      'nome': nome,
      'descricao': descricao,
      'categoria_id': categoriaId,
      'thumbnail_url': _nullableUrl(thumbnailUrl),
      'prompt_padrao': promptPadrao,
      'ativo': ativo,
      'ordem': ordem,
    }).eq('id', id);
  }

  @override
  Future<void> deleteModelo(String id) async {
    await _supabase.from('modelos').delete().eq('id', id);
  }

  String? _nullableUrl(String? url) {
    final t = url?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }
}
