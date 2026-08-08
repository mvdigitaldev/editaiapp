import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Eventos de sessão do editor facial nativo (rollout / telemetria).
class BeautyEditorSessionReporter {
  BeautyEditorSessionReporter({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  Future<void> logEvent(
    String event, {
    String editor = 'native',
    Map<String, dynamic>? metadata,
  }) async {
    debugPrint('[BeautyEditorSession] $event editor=$editor metadata=$metadata');

    final client = _client ?? _tryClient();
    if (client == null) {
      return;
    }

    try {
      await client.from('beauty_editor_session_events').insert({
        'user_id': client.auth.currentUser?.id,
        'event': event,
        'editor': editor,
        'metadata': metadata,
      });
    } catch (_) {
      // Best-effort — não propaga.
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
