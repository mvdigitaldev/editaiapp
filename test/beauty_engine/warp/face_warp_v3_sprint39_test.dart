import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/body_reshape/rendering/native_export_backend.dart';
import 'package:editaiapp/features/editor/beauty_engine/config/face_warp_v3_config.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/face_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/quality/parity_auto_evaluator.dart';
import 'package:editaiapp/features/editor/beauty_engine/quality/parity_checklist_engine.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_mesh_deformation_engine.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_warp_debug_stats.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_mesh_export_warp.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/method_channel_native_face_mesh_backend.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/native_face_mesh_payload.dart';
import 'package:flutter_test/flutter_test.dart';

import '../filters/skin/skin_face_fixture.dart';

void main() {
  const imageSize = Size(640, 960);
  const engine = FaceMeshDeformationEngine();

  group('Sprint 39 — native export + parity auto + swap gate', () {
    setUp(() {
      FaceWarpV3Config.useGpuPiecewiseAffine = true;
      FaceWarpV3Config.useNativePiecewiseExport = true;
    });

    test('NativeFaceMeshPayload serializes atlas textures', () {
      final face = syntheticFace();
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final payload = engine.composeGpuPayload(
        face: face,
        mesh: mesh,
        imageSize: imageSize,
        parameters: const {'jaw': 1.0},
      );
      expect(payload, isNotNull);

      final native = NativeFaceMeshPayload.fromPayload(payload: payload!);
      final args = native.toChannelArgs();
      expect(args['vertexCount'], greaterThan(0));
      expect(args['triangleCount'], greaterThan(0));
      expect(args['cellTriData'], isA<List<int>>());
    });

    test('FaceMeshExportWarp prefers native backend when handler succeeds', () async {
      final face = syntheticFace();
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final payload = engine.composeGpuPayload(
        face: face,
        mesh: mesh,
        imageSize: imageSize,
        parameters: const {'chin': 0.8},
      );
      expect(payload, isNotNull);

      final input = Uint8List(64 * 64 * 4);
      var nativeCalled = false;
      final fakeNative = FakeNativeFaceMeshBackend(
        handler: (req) async {
          nativeCalled = true;
          return Uint8List.fromList(req.rgba);
        },
      );

      final export = FaceMeshExportWarp(nativeBackend: fakeNative);

      final result = await export.apply(
        FaceMeshExportRequest(
          rgba: input,
          width: 64,
          height: 64,
          payload: payload!,
          fullWidth: 640,
          fullHeight: 960,
        ),
      );

      expect(nativeCalled, isTrue);
      expect(result?.backend, ExportWarpBackendKind.metal);
    });

    test('ParityAutoEvaluator passes jaw at synthetic golden range', () {
      final golden = ParityAutoEvaluator.evaluateTool(
        toolKey: 'jaw',
        paramValue: 1.0,
        stats: const FaceWarpDebugStats(
          movedVertices: 12,
          vertexMaxPx: 18.5,
        ),
      );
      expect(golden.verdict, ParityGoldenVerdict.pass);
    });

    test('ParityAutoEvaluator fails when displacement too low', () {
      final golden = ParityAutoEvaluator.evaluateTool(
        toolKey: 'eye_scale',
        paramValue: 0.9,
        stats: const FaceWarpDebugStats(
          movedVertices: 8,
          vertexMaxPx: 0.01,
        ),
      );
      expect(golden.verdict, ParityGoldenVerdict.fail);
    });

    test('ParityChecklistEngine merges golden pass hint', () {
      final items = ParityChecklistEngine.evaluateWarp(
        params: const {'jaw': 1.0},
        warpStats: const FaceWarpDebugStats(
          movedVertices: 12,
          vertexMaxPx: 18.5,
        ),
        warpBackend: 'v3_metal',
      );

      final b3 = items.firstWhere((i) => i.id == 'B3');
      expect(b3.status, ParityChecklistStatus.pass);
      expect(b3.hint, contains('golden'));
    });
  });
}
