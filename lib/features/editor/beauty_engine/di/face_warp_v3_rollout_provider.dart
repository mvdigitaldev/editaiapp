import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/app_remote_config_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../config/face_warp_v3_rollout.dart';
import '../config/face_warp_v3_rollout_applier.dart';
import 'face_editor_rollout_provider.dart';

/// V3 integral — usado em pré-produção e como fallback telemetria.
const _fullV3Snapshot = FaceWarpV3RolloutSnapshot(
  subjectBucket: 0,
  enabled: true,
  useMeshWarpV3: true,
  useDirectMeshRender: true,
  useGpuPiecewiseAffine: true,
  usePostWarpInpaint: true,
  useGpuInpaint: true,
  useNativePiecewiseExport: true,
);

const _fullV3Remote = FaceWarpV3RemoteConfig(
  masterEnabled: true,
  rolloutPercent: 100,
  directRolloutPercent: 100,
  gpuRolloutPercent: 100,
  inpaintRolloutPercent: 100,
  nativeRolloutPercent: 100,
);

/// Config remota Face Warp V3 (Supabase app_settings).
final faceWarpV3RemoteConfigProvider =
    FutureProvider<FaceWarpV3RemoteConfig>((ref) async {
  if (FaceWarpV3Rollout.preProductionForceFull) {
    return _fullV3Remote;
  }

  final ds = ref.watch(appSettingsDataSourceProvider);
  final results = await Future.wait([
    ds.getValue(FaceWarpV3Rollout.settingEnabledKey),
    ds.getValue(FaceWarpV3Rollout.settingRolloutPercentKey),
    ds.getValue(FaceWarpV3Rollout.settingDirectPercentKey),
    ds.getValue(FaceWarpV3Rollout.settingGpuPercentKey),
    ds.getValue(FaceWarpV3Rollout.settingInpaintPercentKey),
    ds.getValue(FaceWarpV3Rollout.settingNativePercentKey),
  ]);

  return FaceWarpV3RemoteConfig(
    masterEnabled: FaceWarpV3Rollout.parseMasterEnabled(results[0]),
    rolloutPercent: FaceWarpV3Rollout.parseRolloutPercent(results[1]),
    directRolloutPercent: FaceWarpV3Rollout.parseRolloutPercent(results[2]),
    gpuRolloutPercent: FaceWarpV3Rollout.parseRolloutPercent(results[3]),
    inpaintRolloutPercent: FaceWarpV3Rollout.parseRolloutPercent(results[4]),
    nativeRolloutPercent: FaceWarpV3Rollout.parseRolloutPercent(results[5]),
  );
});

/// Snapshot V3 resolvida para o sujeito atual (telemetria / debug).
final faceWarpV3RolloutSnapshotProvider =
    FutureProvider<FaceWarpV3RolloutSnapshot>((ref) async {
  if (FaceWarpV3Rollout.preProductionForceFull) {
    return _fullV3Snapshot;
  }

  final remote = await ref.watch(faceWarpV3RemoteConfigProvider.future);
  final auth = ref.watch(authStateProvider);
  final subjectId = await beautyEngineRolloutSubjectId(auth.user?.id);
  return FaceWarpV3RolloutApplier.resolve(
    remote: remote,
    subjectId: subjectId,
  );
});

/// Aplica flags V3 conforme rollout remoto + bucket do usuário.
final faceWarpV3RolloutAppliedProvider =
    FutureProvider<FaceWarpV3RolloutSnapshot>((ref) async {
  if (FaceWarpV3Rollout.preProductionForceFull) {
    FaceWarpV3RolloutApplier.apply(_fullV3Snapshot);
    return _fullV3Snapshot;
  }

  final remote = await ref.watch(faceWarpV3RemoteConfigProvider.future);
  final auth = ref.watch(authStateProvider);
  final subjectId = await beautyEngineRolloutSubjectId(auth.user?.id);
  final snapshot = FaceWarpV3RolloutApplier.resolve(
    remote: remote,
    subjectId: subjectId,
  );
  FaceWarpV3RolloutApplier.apply(snapshot);
  return snapshot;
});
