import '../../../../core/network/dio_client.dart';

/// Encapsula a chamada à Edge Function delete-edits.
/// Deleta registros em edits e arquivos no storage flux-imagens.
class EditsDeleteDataSource {
  Future<int> deleteEdits(List<String> editIds) async {
    if (editIds.isEmpty) return 0;

    final dio = DioClient();
    final response = await dio.instance.post<Map<String, dynamic>>(
      '/functions/v1/delete-edits',
      data: {'edit_ids': editIds},
    );

    final data = response.data;
    if (data == null) {
      throw Exception('Resposta inválida');
    }

    if (response.statusCode != 200) {
      final error = data['error'] as String? ?? 'Erro ao excluir fotos';
      throw Exception(error);
    }

    final deletedCount = data['deleted_count'];
    return (deletedCount is num) ? deletedCount.toInt() : editIds.length;
  }
}
