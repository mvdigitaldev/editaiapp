import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../profile/data/datasources/app_settings_datasource.dart';
import '../config/beauty_engine_rollout.dart';

const _marketplacePublishAdminOnlyKey = 'beauty_marketplace_publish_admin_only';

final _beautyEngineSettingsProvider = Provider<AppSettingsDataSource>((ref) {
  return AppSettingsDataSourceImpl(Supabase.instance.client);
});

/// Estado remoto do rollout (master + percentual).
final beautyEngineRemoteConfigProvider =
    FutureProvider<BeautyEngineRemoteConfig>((ref) async {
  final ds = ref.watch(_beautyEngineSettingsProvider);
  final results = await Future.wait([
    ds.getValue(BeautyEngineRollout.settingEnabledKey),
    ds.getValue(BeautyEngineRollout.settingRolloutPercentKey),
  ]);

  return BeautyEngineRemoteConfig(
    masterEnabled: BeautyEngineRollout.parseMasterEnabled(results[0]),
    rolloutPercent: BeautyEngineRollout.parseRolloutPercent(results[1]),
  );
});

/// `true` quando o usuário atual (ou anon id) está no rollout.
final beautyEngineEnabledProvider = FutureProvider<bool>((ref) async {
  if (kDebugMode) {
    return true;
  }

  final remote = await ref.watch(beautyEngineRemoteConfigProvider.future);
  if (!remote.masterEnabled) {
    return false;
  }

  final auth = ref.watch(authStateProvider);
  final subjectId = await _rolloutSubjectId(auth.user?.id);
  return BeautyEngineRollout.isSubjectEnabled(
    masterEnabled: remote.masterEnabled,
    rolloutPercent: remote.rolloutPercent,
    subjectId: subjectId,
  );
});

class BeautyEngineRemoteConfig {
  const BeautyEngineRemoteConfig({
    required this.masterEnabled,
    required this.rolloutPercent,
  });

  final bool masterEnabled;
  final int rolloutPercent;
}

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

/// `true` quando app_settings exige admin para publicar no marketplace.
final beautyMarketplacePublishAdminOnlyProvider = FutureProvider<bool>((ref) async {
  final ds = ref.watch(_beautyEngineSettingsProvider);
  final value = await ds.getValue(_marketplacePublishAdminOnlyKey);
  return value?.trim().toLowerCase() == 'enable';
});

/// `true` quando o usuário atual pode publicar preset no marketplace.
final canPublishBeautyPresetProvider = FutureProvider<bool>((ref) async {
  final adminOnly = await ref.watch(beautyMarketplacePublishAdminOnlyProvider.future);
  if (!adminOnly) {
    return true;
  }
  final auth = ref.watch(authStateProvider);
  return auth.user?.isAdmin ?? false;
});
