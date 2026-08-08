import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/config/face_warp_v3_config.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/face_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/quality/face_quality_context.dart';
import 'package:editaiapp/features/editor/beauty_engine/quality/parity_checklist_engine.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_mesh_deformation_engine.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_warp_debug_stats.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_mesh_export_warp.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_warp_ghost_mask.dart';
import 'package:flutter_test/flutter_test.dart';

import '../filters/skin/skin_face_fixture.dart';

void main() {
  const imageSize = Size(640, 960);
  const engine = FaceMeshDeformationEngine();

  group('Sprint 38 — export tiled + inpaint GPU + parity', () {
    setUp(() {
      FaceWarpV3Config.useGpuPiecewiseAffine = true;
      FaceWarpV3Config.useDirectMeshRender = true;
      FaceWarpV3Config.usePostWarpInpaint = true;
      FaceWarpV3Config.useGpuInpaint = true;
    });

    test('FaceMeshExportRequest carries tile origin', () {
      final face = syntheticFace();
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final payload = engine.composeGpuPayload(
        face: face,
        mesh: mesh,
        imageSize: imageSize,
        parameters: const {'face_slim': 0.8},
      );
      expect(payload, isNotNull);

      final req = FaceMeshExportRequest(
        rgba: Uint8List(100 * 100 * 4),
        width: 100,
        height: 100,
        payload: payload!,
        tileOriginX: 128,
        tileOriginY: 256,
        fullWidth: 640,
        fullHeight: 960,
      );

      expect(req.resolvedFullWidth, 640);
      expect(req.resolvedFullHeight, 960);
      expect(req.tileOriginX, 128);
    });

    test('FaceWarpGhostMask builds RGBA when lateral warp active', () {
      FaceWarpV3Config.useGpuPiecewiseAffine = false;
      final face = syntheticFace();
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final field = engine.composeWarpField(
        face: face,
        mesh: mesh,
        imageSize: imageSize,
        parameters: const {'eye_distance': 1.0},
        interactivePreview: true,
      );
      expect(field, isNotNull);

      final ghost = FaceWarpGhostMask.buildRgba(
        field: field!,
        parameters: const {'eye_distance': 1.0},
      );
      expect(ghost, isNotNull);
      expect(ghost!.rgba.length, 640 * 960 * 4);
    });

    test('ParityChecklistEngine marks B5 pass when eye_scale active', () {
      final items = ParityChecklistEngine.evaluateWarp(
        params: const {'eye_scale': 0.9},
        warpStats: const FaceWarpDebugStats(
          movedVertices: 12,
          vertexMaxPx: 8.5,
        ),
        warpBackend: 'v3_gpu',
      );

      final b5 = items.firstWhere((i) => i.id == 'B5');
      expect(b5.status, ParityChecklistStatus.pass);
    });

    test('ParityChecklistEngine warns on small face', () {
      final items = ParityChecklistEngine.evaluateWarp(
        params: const {'jaw': 1.0},
        quality: const FaceQualityContext(
          metrics: FaceQualityMetrics(
            hasFace: true,
            faceWidthPx: 120,
            faceHeightPx: 160,
          ),
          score: FaceQualityScore(
            sharpness: 0.5,
            lighting: 0.5,
            pose: 0.5,
            integrity: 0.5,
          ),
        ),
        warpStats: const FaceWarpDebugStats(
          movedVertices: 10,
          vertexMaxPx: 5,
        ),
      );

      final b3 = items.firstWhere((i) => i.id == 'B3');
      expect(b3.status, ParityChecklistStatus.warn);
      expect(b3.hint, contains('200px'));
    });
  });
}
