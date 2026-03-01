import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/categoria_model.dart';
import '../models/modelo_model.dart';

abstract class ModelosDataSource {
  Future<List<CategoriaModel>> getCategorias();
  Future<List<ModeloModel>> getModelosPorCategoria(String categoriaId);
}

class ModelosDataSourceImpl implements ModelosDataSource {
  final SupabaseClient _supabase;

  ModelosDataSourceImpl(this._supabase);

  @override
  Future<List<CategoriaModel>> getCategorias() async {
    final response = await _supabase
        .from('categorias')
        .select('id, nome, slug, ordem, ativo')
        .eq('ativo', true)
        .order('ordem', ascending: true);

    return (response as List)
        .map((json) => CategoriaModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<ModeloModel>> getModelosPorCategoria(String categoriaId) async {
    final response = await _supabase
        .from('modelos')
        .select('id, nome, descricao, categoria_id, thumbnail_url, prompt_padrao, ativo, ordem')
        .eq('ativo', true)
        .eq('categoria_id', categoriaId)
        .order('ordem', ascending: true);

    return (response as List)
        .map((json) => ModeloModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}
