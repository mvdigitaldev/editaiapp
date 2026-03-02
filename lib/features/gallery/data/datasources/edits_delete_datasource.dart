import 'package:supabase_flutter/supabase_flutter.dart';

/// Encapsula a chamada à Edge Function delete-edits.
/// Deleta registros em edits e arquivos no storage flux-imagens.
/// Usa functions.invoke para garantir envio correto do JWT.
class EditsDeleteDataSource {
  Future<int> deleteEdits(List<String> editIds) async {
    if (editIds.isEmpty) return 0;

    // Garantir sessão válida antes da requisição (evita 401 por token expirado)
    final session = await Supabase.instance.client.auth.refreshSession();
    if (session.session == null) {
      throw Exception('Sessão expirada. Faça login novamente.');
    }

    final res = await Supabase.instance.client.functions.invoke(
      'delete-edits',
      body: {'edit_ids': editIds},
    );

    final data = res.data;
    if (data == null) {
      throw Exception(res.status == 401 ? 'Sessão expirada. Faça login novamente.' : 'Resposta inválida');
    }

    final map = data is Map ? Map<String, dynamic>.from(data) : null;
    if (map == null) {
      throw Exception('Resposta inválida');
    }

    if (res.status != 200) {
      final error = map['error'] as String? ?? 'Erro ao excluir fotos';
      throw Exception(error);
    }

    final deletedCount = map['deleted_count'];
    return (deletedCount is num) ? deletedCount.toInt() : editIds.length;
  }
}
