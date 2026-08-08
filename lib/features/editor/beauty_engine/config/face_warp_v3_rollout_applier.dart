import 'face_warp_v3_config.dart';
import 'face_warp_v3_rollout.dart';

/// Aplica rollout remoto V3 em [FaceWarpV3Config] (Sprint 41).
abstract final class FaceWarpV3RolloutApplier {
  static FaceWarpV3RolloutSnapshot resolve({
    required FaceWarpV3RemoteConfig remote,
    required String subjectId,
  }) {
    if (!remote.masterEnabled) {
      return FaceWarpV3RolloutSnapshot.disabled;
    }

    final bucket = FaceWarpV3Rollout.subjectBucket(subjectId);
    final inMaster = FaceWarpV3Rollout.isSubjectEnabled(
      masterEnabled: remote.masterEnabled,
      rolloutPercent: remote.rolloutPercent,
      subjectId: subjectId,
    );
    if (!inMaster) {
      return FaceWarpV3RolloutSnapshot(
        subjectBucket: bucket,
        enabled: false,
        useMeshWarpV3: false,
        useDirectMeshRender: false,
        useGpuPiecewiseAffine: false,
        usePostWarpInpaint: false,
        useGpuInpaint: false,
        useNativePiecewiseExport: false,
      );
    }

    final gpu = FaceWarpV3Rollout.isSubjectEnabled(
      masterEnabled: true,
      rolloutPercent: remote.gpuRolloutPercent,
      subjectId: subjectId,
    );
    final inpaint = FaceWarpV3Rollout.isSubjectEnabled(
      masterEnabled: true,
      rolloutPercent: remote.inpaintRolloutPercent,
      subjectId: subjectId,
    );
    final direct = FaceWarpV3Rollout.isSubjectEnabled(
      masterEnabled: true,
      rolloutPercent: remote.directRolloutPercent,
      subjectId: subjectId,
    );
    final nativeExport = FaceWarpV3Rollout.isSubjectEnabled(
      masterEnabled: true,
      rolloutPercent: remote.nativeRolloutPercent,
      subjectId: subjectId,
    );

    return FaceWarpV3RolloutSnapshot(
      subjectBucket: bucket,
      enabled: true,
      useMeshWarpV3: true,
      useDirectMeshRender: direct,
      useGpuPiecewiseAffine: gpu,
      usePostWarpInpaint: inpaint,
      useGpuInpaint: inpaint,
      useNativePiecewiseExport: nativeExport && gpu,
    );
  }

  static void apply(FaceWarpV3RolloutSnapshot snapshot) {
    FaceWarpV3Config.enabled = snapshot.enabled;
    FaceWarpV3Config.useMeshWarpV3 = snapshot.useMeshWarpV3;
    FaceWarpV3Config.useDirectMeshRender = snapshot.useDirectMeshRender;
    FaceWarpV3Config.useGpuPiecewiseAffine = snapshot.useGpuPiecewiseAffine;
    FaceWarpV3Config.usePostWarpInpaint = snapshot.usePostWarpInpaint;
    FaceWarpV3Config.useGpuInpaint = snapshot.useGpuInpaint;
    FaceWarpV3Config.useNativePiecewiseExport = snapshot.useNativePiecewiseExport;
  }

  static void resetProduction() {
    apply(FaceWarpV3RolloutSnapshot.disabled);
  }
}
