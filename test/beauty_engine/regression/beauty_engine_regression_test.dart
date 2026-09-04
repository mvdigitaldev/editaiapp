import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/legacy_body_parameter_adapter.dart';
import 'package:editaiapp/features/editor/beauty_engine/controllers/beauty_engine_controller.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/body/body_filter_pipeline.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/face_filter_pipeline.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/skin_filter_pipeline.dart';
import 'package:editaiapp/features/editor/beauty_engine/face_mesh/face_mesh_detector_stub.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/body_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/mesh_engine_stub.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/beauty_preset.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/image_source.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/pose_landmark.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/pose_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/processing_pipeline.dart';
import 'package:editaiapp/features/editor/beauty_engine/performance/adaptive_preview_policy.dart';
import 'package:editaiapp/features/editor/beauty_engine/performance/tiled_export_engine.dart';
import 'package:editaiapp/features/editor/beauty_engine/pose/pose_detector_stub.dart';
import 'package:editaiapp/features/editor/beauty_engine/presets/beauty_preset_remote_record.dart';
import 'package:editaiapp/features/editor/beauty_engine/presets/bundled_preset_loader.dart';
import 'package:editaiapp/features/editor/beauty_engine/presets/bundled_presets.dart';
import 'package:editaiapp/features/editor/beauty_engine/presets/preset_sync_service.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/gpu_renderer_stub.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/warp_engine_stub.dart';
import 'package:flutter_test/flutter_test.dart';

/// Suite de regressão Sprint 26 — smoke tests face + body + presets + sync + perf.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const imageSize = Size(640, 960);
  const sync = PresetSyncService();

  group('Regression — face filters', () {
    const pipeline = FaceFilterPipeline();

    test(
        'hairline, jaw, jaw_angle, chin, v_chin, v_shape and cheekbone are the facial warp keys and activate the pipeline',
        () {
      expect(
        FaceFilterPipeline.faceWarpParameterKeys,
        [
          'jaw',
          'jaw_angle',
          'chin',
          'v_chin',
          'v_shape',
          'cheekbone',
          'hairline',
        ],
      );
      expect(
        FaceFilterPipeline.eyebrowParameterKeys,
        ['eyebrow_height', 'eyebrow_width', 'eyebrow_end'],
      );
      expect(pipeline.hasActiveWarp({'head': 0.5}), isTrue);
      expect(pipeline.hasActiveWarp({'head': -0.5}), isTrue);
      expect(pipeline.hasActiveWarp({'head': 0}), isFalse);
      expect(pipeline.hasActiveWarp({'eyebrow_height': 0.5}), isTrue);
      expect(pipeline.hasActiveWarp({'eyebrow_height': -0.5}), isTrue);
      expect(pipeline.hasActiveWarp({'eyebrow_height': 0}), isFalse);
      expect(pipeline.hasActiveWarp({'eyebrow_height_left': 0.5}), isTrue);
      expect(pipeline.hasActiveWarp({'eyebrow_height_right': -0.4}), isTrue);
      expect(pipeline.hasActiveWarp({'eyebrow_width': 0.5}), isTrue);
      expect(pipeline.hasActiveWarp({'eyebrow_width': -0.5}), isTrue);
      expect(pipeline.hasActiveWarp({'eyebrow_width': 0}), isFalse);
      expect(pipeline.hasActiveWarp({'eyebrow_width_left': 0.5}), isTrue);
      expect(pipeline.hasActiveWarp({'eyebrow_width_right': -0.4}), isTrue);
      expect(pipeline.hasActiveWarp({'eyebrow_end': 0.5}), isTrue);
      expect(pipeline.hasActiveWarp({'eyebrow_end': -0.5}), isTrue);
      expect(pipeline.hasActiveWarp({'eyebrow_end': 0}), isFalse);
      expect(pipeline.hasActiveWarp({'eyebrow_end_left': 0.5}), isTrue);
      expect(pipeline.hasActiveWarp({'eyebrow_end_right': -0.4}), isTrue);
      expect(pipeline.hasActiveWarp({'hairline': 0.5}), isTrue);
      expect(pipeline.hasActiveWarp({'hairline': -0.5}), isTrue);
      expect(pipeline.hasActiveWarp({'hairline': 0}), isFalse);
      expect(pipeline.hasActiveWarp({'jaw': 0.5}), isTrue);
      expect(pipeline.hasActiveWarp({'jaw': 0}), isFalse);
      expect(pipeline.hasActiveWarp({'jaw_angle': 0.5}), isTrue);
      expect(pipeline.hasActiveWarp({'jaw_angle': -0.5}), isTrue);
      expect(pipeline.hasActiveWarp({'jaw_angle': 0}), isFalse);
      expect(pipeline.hasActiveWarp({'jaw_angle_left': 0.5}), isTrue);
      expect(pipeline.hasActiveWarp({'jaw_angle_right': -0.4}), isTrue);
      expect(pipeline.hasActiveWarp({'chin': 0.8}), isTrue);
      expect(pipeline.hasActiveWarp({'chin': -0.5}), isTrue);
      expect(pipeline.hasActiveWarp({'chin': 0}), isFalse);
      expect(pipeline.hasActiveWarp({'v_chin': 0.5}), isTrue);
      expect(pipeline.hasActiveWarp({'v_chin': -0.5}), isTrue);
      expect(pipeline.hasActiveWarp({'v_chin': 0}), isFalse);
      expect(pipeline.hasActiveWarp({'v_chin_left': 0.5}), isTrue);
      expect(pipeline.hasActiveWarp({'v_chin_right': -0.4}), isTrue);
      expect(pipeline.hasActiveWarp({'v_shape': 0.5}), isTrue);
      expect(pipeline.hasActiveWarp({'v_shape': -0.5}), isTrue);
      expect(pipeline.hasActiveWarp({'v_shape': 0}), isFalse);
      expect(pipeline.hasActiveWarp({'v_shape_left': 0.5}), isTrue);
      expect(pipeline.hasActiveWarp({'v_shape_right': -0.4}), isTrue);
      expect(pipeline.hasActiveWarp({'cheekbone': 0.5}), isTrue);
      expect(pipeline.hasActiveWarp({'cheekbone': -0.5}), isTrue);
      expect(pipeline.hasActiveWarp({'cheekbone': 0}), isFalse);
      expect(pipeline.hasActiveWarp({'cheekbone_left': 0.5}), isTrue);
      expect(pipeline.hasActiveWarp({'cheekbone_right': -0.4}), isTrue);
    });
  });

  group('Regression — body filters', () {
    late BodyFilterPipeline pipeline;
    late PoseResult pose;

    setUp(() {
      pipeline = const BodyFilterPipeline();
      pose = _fakeFullBodyPose();
    });

    for (final filter in BodyFilterPipeline.allFilters) {
      test('${filter.parameterKey} at 0.5 composes without error', () {
        final mesh = const BodyMeshBuilder().build(pose, imageSize);
        final field = pipeline.compose(
          mesh: mesh,
          pose: pose,
          imageSize: imageSize,
          parameters: {filter.parameterKey: 0.5},
        );
        expect(field.controlPoints, isNotEmpty);
      });
    }

    test('V2-only keys expose reshape plan without MLS control points', () {
      for (final key in LegacyBodyParameterAdapter.v2MeshParameterKeys) {
        final plan = pipeline.createReshapePlan(
          imageSize: imageSize,
          parameters: {key: 0.5},
        );
        expect(plan.isIdentity, isFalse, reason: key);
        expect(
          pipeline.hasActiveBodyWarp({key: 0.5}),
          isTrue,
          reason: key,
        );
      }
    });
  });

  group('Regression — skin filters', () {
    const pipeline = SkinFilterPipeline();

    for (final key in SkinFilterPipeline.skinParameterKeys) {
      test('$key at 0.5 is active', () {
        expect(
          pipeline.hasActiveSkin({key: 0.5}),
          isTrue,
        );
      });
    }
  });

  group('Regression — bundled presets', () {
    tearDown(BundledBeautyPresets.debugResetCache);

    test('loads 9 shipped presets from assets', () async {
      final presets = await const BundledPresetLoader().load();
      expect(presets, hasLength(9));
    });

    test('each bundled preset round-trips JSON', () async {
      final presets = await const BundledPresetLoader().load();
      for (final preset in presets) {
        final restored = BeautyPreset.fromJson(preset.toJson());
        expect(restored.id, preset.id);
        expect(restored.name, preset.name);
      }
    });
  });

  group('Regression — preset sync', () {
    test('LWW merge prefers newer remote', () {
      final result = sync.merge(
        localPresets: [
          BeautyPreset(
            id: 'user_x',
            name: 'Local',
            updatedAt: DateTime.utc(2026, 1, 1),
            remoteId: 'remote-x',
          ),
        ],
        remoteRecords: [
          BeautyPresetRemoteRecord(
            id: 'remote-x',
            userId: 'user-1',
            clientId: 'user_x',
            name: 'Remote',
            preset: const BeautyPreset(id: 'user_x', name: 'Remote'),
            updatedAt: DateTime.utc(2026, 6, 1),
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        ],
      );
      expect(result.mergedLocal.first.name, 'Remote');
    });

    test('local-only preset marked for push', () {
      final result = sync.merge(
        localPresets: const [
          BeautyPreset(id: 'user_new', name: 'New'),
        ],
        remoteRecords: const [],
      );
      expect(result.pushedClientIds, {'user_new'});
    });
  });

  group('Regression — performance policy', () {
    test('selfie uses 720p max edge', () {
      final source = ImageSource(bytes: Uint8List(0), width: 1280, height: 720);
      expect(AdaptivePreviewPolicy.maxEdgeForSource(source), 720);
    });

    test('4MP photo uses 1080p max edge', () {
      final source =
          ImageSource(bytes: Uint8List(0), width: 2560, height: 1600);
      expect(AdaptivePreviewPolicy.maxEdgeForSource(source), 1080);
    });

    test('12MP triggers tiled export', () {
      final source =
          ImageSource(bytes: Uint8List(0), width: 4000, height: 3000);
      expect(AdaptivePreviewPolicy.shouldUseTiledExport(source), isTrue);
      expect(TiledExportEngine().shouldUseTiledExport(source), isTrue);
    });

    test('1080p does not trigger tiled export', () {
      final source =
          ImageSource(bytes: Uint8List(0), width: 1920, height: 1080);
      expect(AdaptivePreviewPolicy.shouldUseTiledExport(source), isFalse);
    });
  });

  group('Regression — controller stub path', () {
    test('process completes with detector stubs', () async {
      final controller = BeautyEngineController(
        faceDetector: const FaceMeshDetectorStub(),
        poseDetector: const PoseDetectorStub(),
        meshEngine: const MeshEngineStub(),
        warpEngine: const WarpEngineStub(),
        gpuRenderer: GPURendererStub(),
      );

      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final source = ImageSource(bytes: bytes, width: 2, height: 2);

      final frame = await controller.process(
        source: source,
        pipeline: const ProcessingPipeline(),
      );
      expect(frame.bytes, bytes);
      expect(frame.width, 2);
      expect(frame.height, 2);
    });
  });
}

PoseResult _fakeFullBodyPose({double visibility = 0.9}) {
  final landmarks = List.generate(
    PoseResult.expectedLandmarkCount,
    (index) {
      final x = 0.45 + (index % 5) * 0.02;
      final y = 0.1 + (index / PoseResult.expectedLandmarkCount) * 0.85;
      return PoseLandmark(
        index: index,
        normalized: Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0)),
        visibility: visibility,
      );
    },
  );

  return PoseResult(
    landmarks: landmarks,
    boundingBox: const Rect.fromLTWH(0.1, 0.05, 0.8, 0.9),
    isPartial: false,
  );
}
