import 'beauty_engine_rollout.dart';

/// Rollout remoto do Face Warp V3 (Sprint 38–41).
abstract final class FaceWarpV3Rollout {
  /// Pré-produção: V3 100% ligado no app (ignora buckets remotos).
  /// Defina `false` antes do release na loja.
  static const preProductionForceFull = true;

  static const settingEnabledKey = 'face_warp_v3_enabled';
  static const settingRolloutPercentKey = 'face_warp_v3_rollout_percent';
  static const settingDirectPercentKey = 'face_warp_v3_direct_percent';
  static const settingGpuPercentKey = 'face_warp_v3_gpu_percent';
  static const settingInpaintPercentKey = 'face_warp_v3_inpaint_percent';
  static const settingNativePercentKey = 'face_warp_v3_native_percent';

  static bool isSubjectEnabled({
    required bool masterEnabled,
    required int rolloutPercent,
    required String subjectId,
  }) {
    return BeautyEngineRollout.isSubjectEnabled(
      masterEnabled: masterEnabled,
      rolloutPercent: rolloutPercent,
      subjectId: subjectId,
    );
  }

  static bool parseMasterEnabled(String? raw) {
    return raw?.trim().toLowerCase() == 'enable';
  }

  static int parseRolloutPercent(String? raw) {
    return BeautyEngineRollout.parseRolloutPercent(raw);
  }

  static int subjectBucket(String subjectId) {
    return BeautyEngineRollout.stableBucket(subjectId);
  }
}

/// Config remota Face Warp V3 lida do Supabase `app_settings`.
class FaceWarpV3RemoteConfig {
  const FaceWarpV3RemoteConfig({
    required this.masterEnabled,
    required this.rolloutPercent,
    required this.directRolloutPercent,
    required this.gpuRolloutPercent,
    required this.inpaintRolloutPercent,
    required this.nativeRolloutPercent,
  });

  final bool masterEnabled;
  final int rolloutPercent;
  final int directRolloutPercent;
  final int gpuRolloutPercent;
  final int inpaintRolloutPercent;
  final int nativeRolloutPercent;

  static const disabled = FaceWarpV3RemoteConfig(
    masterEnabled: false,
    rolloutPercent: 0,
    directRolloutPercent: 0,
    gpuRolloutPercent: 0,
    inpaintRolloutPercent: 0,
    nativeRolloutPercent: 0,
  );
}

/// Flags V3 resolvidas para um sujeito (bucket estável).
class FaceWarpV3RolloutSnapshot {
  const FaceWarpV3RolloutSnapshot({
    required this.subjectBucket,
    required this.enabled,
    required this.useMeshWarpV3,
    required this.useDirectMeshRender,
    required this.useGpuPiecewiseAffine,
    required this.usePostWarpInpaint,
    required this.useGpuInpaint,
    required this.useNativePiecewiseExport,
  });

  final int subjectBucket;
  final bool enabled;
  final bool useMeshWarpV3;
  final bool useDirectMeshRender;
  final bool useGpuPiecewiseAffine;
  final bool usePostWarpInpaint;
  final bool useGpuInpaint;
  final bool useNativePiecewiseExport;

  static const disabled = FaceWarpV3RolloutSnapshot(
    subjectBucket: 0,
    enabled: false,
    useMeshWarpV3: false,
    useDirectMeshRender: false,
    useGpuPiecewiseAffine: false,
    usePostWarpInpaint: false,
    useGpuInpaint: false,
    useNativePiecewiseExport: false,
  );

  Map<String, dynamic> toTelemetry() => {
        'v3_bucket': subjectBucket,
        'v3_enabled': enabled,
        'v3_mesh': useMeshWarpV3,
        'v3_direct': useDirectMeshRender,
        'v3_gpu': useGpuPiecewiseAffine,
        'v3_inpaint': usePostWarpInpaint,
        'v3_inpaint_gpu': useGpuInpaint,
        'v3_native_export': useNativePiecewiseExport,
      };
}
