import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Extrai `edit_id` do corpo JSON de erro da Edge Function.
String? editIdFromDioResponse(DioException e) {
  final data = e.response?.data;
  if (data is Map && data['edit_id'] is String) {
    final id = data['edit_id'] as String;
    return id.isNotEmpty ? id : null;
  }
  return null;
}

/// Rede de segurança: libera reserva pendente se a Edge falhou após reservar créditos.
Future<void> tryReleasePendingReservationForEdit(String? editId) async {
  if (editId == null || editId.isEmpty) return;
  try {
    await Supabase.instance.client.rpc<void>(
      'user_release_pending_reservation_for_edit',
      params: {
        'p_edit_id': editId,
        'p_reason': 'client_after_edge_error',
      },
    );
  } catch (_) {}
}
