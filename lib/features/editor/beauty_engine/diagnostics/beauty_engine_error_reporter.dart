import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reporta erros do Beauty Engine para monitoramento pós-release (Sprint 27).
class BeautyEngineErrorReporter {
  BeautyEngineErrorReporter({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  Future<void> report(
    Object error, {
    String? context,
    StackTrace? stackTrace,
  }) async {
    final message = error.toString();
    debugPrint('[BeautyEngine${context != null ? '/$context' : ''}] $message');
    if (stackTrace != null) {
      debugPrint(stackTrace.toString());
    }

    final client = _client ?? _tryClient();
    if (client == null) {
      return;
    }

    try {
      final userId = client.auth.currentUser?.id;
      await client.from('beauty_engine_error_logs').insert({
        'user_id': userId,
        'context': context,
        'message': message.length > 2000 ? message.substring(0, 2000) : message,
      });
    } catch (_) {
      // Telemetria best-effort — não propaga.
    }
  }

  SupabaseClient? _tryClient() {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }
}
