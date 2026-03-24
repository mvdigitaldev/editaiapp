import 'package:postgrest/postgrest.dart';

/// Mensagens amigáveis para erros comuns do PostgREST (RLS, unique, FK).
String postgrestUserMessage(Object e) {
  if (e is PostgrestException) {
    final code = e.code;
    final msg = e.message.toLowerCase();
    if (code == '42501' ||
        msg.contains('permission') ||
        msg.contains('policy') ||
        msg.contains('row-level security')) {
      return 'Sem permissão para esta ação.';
    }
    if (code == '23505') {
      return 'Já existe um registro com este slug ou outro valor único.';
    }
    if (code == '23503') {
      return 'Não foi possível excluir: ainda há modelos ou outras referências.';
    }
    return e.message;
  }
  return e.toString();
}
