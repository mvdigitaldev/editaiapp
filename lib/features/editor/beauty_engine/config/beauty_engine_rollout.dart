import 'dart:convert';

/// Rollout gradual do Beauty Engine por bucket estável 0–99 (Sprint 27).
abstract final class BeautyEngineRollout {
  static const settingEnabledKey = 'beauty_engine_enabled';
  static const settingRolloutPercentKey = 'beauty_engine_rollout_percent';
  static const anonymousSubjectStorageKey = 'beauty_engine_rollout_anon_id';

  /// `true` quando master switch ligado e o sujeito cai no bucket do rollout.
  static bool isSubjectEnabled({
    required bool masterEnabled,
    required int rolloutPercent,
    required String subjectId,
    bool forceEnable = false,
  }) {
    if (forceEnable) {
      return true;
    }
    if (!masterEnabled) {
      return false;
    }
    final clamped = rolloutPercent.clamp(0, 100);
    if (clamped >= 100) {
      return true;
    }
    if (clamped <= 0) {
      return false;
    }
    return stableBucket(subjectId) < clamped;
  }

  static int parseRolloutPercent(String? raw) {
    final parsed = int.tryParse(raw?.trim() ?? '');
    if (parsed == null) {
      return 0;
    }
    return parsed.clamp(0, 100);
  }

  static bool parseMasterEnabled(String? raw) {
    return raw?.trim().toLowerCase() == 'enable';
  }

  /// Bucket determinístico 0–99 para rollout gradual.
  static int stableBucket(String subjectId) {
    final bytes = utf8.encode(subjectId);
    var hash = 2166136261;
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * 16777619) & 0xffffffff;
    }
    return hash % 100;
  }
}
