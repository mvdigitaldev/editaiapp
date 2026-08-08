import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../config/beauty_engine_rollout.dart';

Future<String> _rolloutSubjectId(String? userId) async {
  if (userId != null && userId.isNotEmpty) {
    return userId;
  }

  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString(BeautyEngineRollout.anonymousSubjectStorageKey);
  if (existing != null && existing.isNotEmpty) {
    return existing;
  }

  final generated = const Uuid().v4();
  await prefs.setString(BeautyEngineRollout.anonymousSubjectStorageKey, generated);
  return generated;
}

/// Subject id estável para rollout (usuário autenticado ou anônimo).
Future<String> beautyEngineRolloutSubjectId(String? userId) =>
    _rolloutSubjectId(userId);
