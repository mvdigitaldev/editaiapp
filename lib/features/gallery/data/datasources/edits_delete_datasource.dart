import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/app_config.dart';

/// Deleta registros em `edits` e arquivos correspondentes no storage (`flux-imagens`)
/// usando diretamente o Supabase SDK, sem depender da Edge Function `delete-edits`.
class EditsDeleteDataSource {
  EditsDeleteDataSource({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<int> deleteEdits(List<String> editIds) async {
    if (editIds.isEmpty) return 0;

    // Garantir sessão válida antes da requisição (evita 401 por token expirado)
    final session = await _client.auth.refreshSession();
    if (session.session == null) {
      throw Exception('Sessão expirada. Faça login novamente.');
    }

    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('Usuário não autenticado.');
    }

    // Buscar apenas edits que pertencem ao usuário autenticado
    // Para uuid, o PostgREST aceita o formato: (uuid1,uuid2,uuid3)
    final idsList = editIds.join(',');
    final response = await _client
        .from('edits')
        .select('id, image_url')
        .filter('id', 'in', '($idsList)')
        .eq('user_id', user.id);

    final rows = (response as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return 0;

    final idsToDelete = <String>[];
    final storagePaths = <String>[];

    for (final row in rows) {
      final id = row['id'] as String?;
      final imageUrl = row['image_url'] as String?;
      if (id != null) {
        idsToDelete.add(id);
      }
      if (imageUrl != null && imageUrl.isNotEmpty) {
        final path = _extractStoragePathFromPublicUrl(imageUrl);
        if (path != null) {
          storagePaths.add(path);
        }
      }
    }

    // Remover arquivos do storage; falha aqui não impede exclusão das linhas
    if (storagePaths.isNotEmpty) {
      try {
        await _client.storage.from(AppConfig.editsBucket).remove(storagePaths);
      } catch (_) {
        // Ignorar erro de storage, mas poderíamos logar em um serviço de logging.
      }
    }

    if (idsToDelete.isEmpty) return 0;

    var deletedCount = 0;

    try {
      // Tentativa de delete em batch
      final idsToDeleteList = idsToDelete.join(',');
      await _client
          .from('edits')
          .delete()
          .filter('id', 'in', '($idsToDeleteList)')
          .eq('user_id', user.id);
      deletedCount = idsToDelete.length;
    } catch (_) {
      // Fallback: tentar deletar um a um para não falhar tudo por causa de um registro
      for (final id in idsToDelete) {
        try {
          await _client.from('edits').delete().eq('id', id).eq('user_id', user.id);
          deletedCount++;
        } catch (_) {
          // Ignorar falha individual; usuário continuará vendo essa foto na próxima atualização.
        }
      }
    }

    return deletedCount;
  }

  String? _extractStoragePathFromPublicUrl(String imageUrl) {
    final prefix = '${AppConfig.editsBucket}/';
    final idx = imageUrl.indexOf(prefix);
    if (idx == -1) return null;

    var path = imageUrl.substring(idx + prefix.length);
    final queryIndex = path.indexOf('?');
    if (queryIndex != -1) {
      path = path.substring(0, queryIndex);
    }
    path = path.trim();
    return path.isEmpty ? null : path;
  }

  /// Helper opcional para deletar uma única edição.
  Future<void> deleteSingleEdit(String editId) async {
    await deleteEdits([editId]);
  }
}
