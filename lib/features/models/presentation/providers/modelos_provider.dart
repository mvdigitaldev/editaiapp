import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/datasources/modelos_datasource.dart';
import '../../data/models/categoria_model.dart';
import '../../data/models/modelo_model.dart';

final modelosDataSourceProvider = Provider<ModelosDataSource>((ref) {
  return ModelosDataSourceImpl(ref.watch(supabaseClientProvider));
});

/// Lista de categorias ativas para a tela inicial de Modelos.
final categoriasProvider = FutureProvider<List<CategoriaModel>>((ref) async {
  final user = ref.watch(authStateProvider).user;
  if (user == null) return [];
  final ds = ref.watch(modelosDataSourceProvider);
  return ds.getCategorias();
});

/// Lista de modelos por categoria (para a tela de modelos da categoria).
final modelosPorCategoriaProvider =
    FutureProvider.family<List<ModeloModel>, String>((ref, categoriaId) async {
  final user = ref.watch(authStateProvider).user;
  if (user == null) return [];
  final ds = ref.watch(modelosDataSourceProvider);
  return ds.getModelosPorCategoria(categoriaId);
});
