import 'package:editaiapp/features/editor/beauty_engine/config/beauty_engine_rollout.dart';
import 'package:editaiapp/features/editor/beauty_engine/config/face_warp_v3_config.dart';
import 'package:editaiapp/features/editor/beauty_engine/config/face_warp_v3_rollout.dart';
import 'package:editaiapp/features/editor/beauty_engine/config/face_warp_v3_rollout_applier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Sprint 41 — production rollout V3', () {
    setUp(() {
      FaceWarpV3RolloutApplier.resetProduction();
    });

    test('master disabled resets all flags', () {
      FaceWarpV3Config.enabled = true;
      FaceWarpV3Config.useGpuPiecewiseAffine = true;

      final snapshot = FaceWarpV3RolloutApplier.resolve(
        remote: FaceWarpV3RemoteConfig.disabled,
        subjectId: 'user-a',
      );

      FaceWarpV3RolloutApplier.apply(snapshot);

      expect(FaceWarpV3Config.enabled, isFalse);
      expect(FaceWarpV3Config.useMeshWarpV3, isFalse);
      expect(FaceWarpV3Config.useGpuPiecewiseAffine, isFalse);
      expect(FaceWarpV3Config.useDirectMeshRender, isFalse);
      expect(FaceWarpV3Config.useNativePiecewiseExport, isFalse);
    });

    test('master rollout percent gates mesh V3', () {
      const remote = FaceWarpV3RemoteConfig(
        masterEnabled: true,
        rolloutPercent: 50,
        directRolloutPercent: 100,
        gpuRolloutPercent: 100,
        inpaintRolloutPercent: 100,
        nativeRolloutPercent: 100,
      );

      String? inSubject;
      String? outSubject;
      for (var i = 0; i < 200; i++) {
        final id = 'subject-$i';
        final bucket = BeautyEngineRollout.stableBucket(id);
        if (inSubject == null && bucket < 50) {
          inSubject = id;
        }
        if (outSubject == null && bucket >= 50) {
          outSubject = id;
        }
        if (inSubject != null && outSubject != null) {
          break;
        }
      }

      expect(inSubject, isNotNull);
      expect(outSubject, isNotNull);

      expect(
        FaceWarpV3RolloutApplier.resolve(
          remote: remote,
          subjectId: inSubject!,
        ).enabled,
        isTrue,
      );
      expect(
        FaceWarpV3RolloutApplier.resolve(
          remote: remote,
          subjectId: outSubject!,
        ).enabled,
        isFalse,
      );
    });

    test('sub-flags respect independent rollout percents', () {
      const remote = FaceWarpV3RemoteConfig(
        masterEnabled: true,
        rolloutPercent: 100,
        directRolloutPercent: 100,
        gpuRolloutPercent: 0,
        inpaintRolloutPercent: 0,
        nativeRolloutPercent: 100,
      );

      final snapshot = FaceWarpV3RolloutApplier.resolve(
        remote: remote,
        subjectId: 'subject-1',
      );

      expect(snapshot.enabled, isTrue);
      expect(snapshot.useDirectMeshRender, isTrue);
      expect(snapshot.useGpuPiecewiseAffine, isFalse);
      expect(snapshot.usePostWarpInpaint, isFalse);
      expect(snapshot.useNativePiecewiseExport, isFalse);
    });

    test('native export requires gpu bucket', () {
      const remote = FaceWarpV3RemoteConfig(
        masterEnabled: true,
        rolloutPercent: 100,
        directRolloutPercent: 0,
        gpuRolloutPercent: 0,
        inpaintRolloutPercent: 0,
        nativeRolloutPercent: 100,
      );

      final snapshot = FaceWarpV3RolloutApplier.resolve(
        remote: remote,
        subjectId: 'subject-native',
      );

      expect(snapshot.useNativePiecewiseExport, isFalse);
    });

    test('telemetry payload includes bucket and flags', () {
      const snapshot = FaceWarpV3RolloutSnapshot(
        subjectBucket: 42,
        enabled: true,
        useMeshWarpV3: true,
        useDirectMeshRender: true,
        useGpuPiecewiseAffine: false,
        usePostWarpInpaint: true,
        useGpuInpaint: true,
        useNativePiecewiseExport: false,
      );

      expect(snapshot.toTelemetry()['v3_bucket'], 42);
      expect(snapshot.toTelemetry()['v3_direct'], isTrue);
      expect(snapshot.toTelemetry()['v3_gpu'], isFalse);
    });
  });
}
