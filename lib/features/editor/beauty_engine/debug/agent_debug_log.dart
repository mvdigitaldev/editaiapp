import 'dart:convert';
import 'dart:io';

/// Logs NDJSON para sessão de debug do agente (face_slim).
abstract final class AgentDebugLog {
  static const _path =
      '/Users/leonardo/Documents/Projetos/editaiapp/.cursor/debug-13c8af.log';
  static const _sessionId = '13c8af';

  static void write({
    required String location,
    required String message,
    required Map<String, dynamic> data,
    required String hypothesisId,
    String runId = 'pre-fix',
  }) {
    // #region agent log
    try {
      final payload = jsonEncode({
        'sessionId': _sessionId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'location': location,
        'message': message,
        'data': data,
        'hypothesisId': hypothesisId,
        'runId': runId,
      });
      File(_path).writeAsStringSync('$payload\n', mode: FileMode.append);
    } catch (_) {}
    // #endregion
  }
}
