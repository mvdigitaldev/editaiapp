import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/anatomical_intent.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/anatomical_zone.dart';
import 'package:editaiapp/features/editor/beauty_engine/config/face_warp_v3_config.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/face_filter_pipeline.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/face_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/anatomical_intent_factory.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_mesh_deformation_engine.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/pilot_warp_displacement.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/vertex_role_map.dart';
import 'package:flutter_test/flutter_test.dart';

import '../filters/skin/skin_face_fixture.dart';

void main() {
  const imageSize = Size(640, 960);
  const engine = FaceMeshDeformationEngine();

  group('Sprint 36 — contour + nose pilot', () {
    setUp(() {
      FaceWarpV3Config.useDirectMeshRender = true;
      FaceWarpV3Config.useGpuPiecewiseAffine = false;
    });
    test('all 22 warp tools use pilot mode', () {
      final context = FaceAnatomyContext(
        face: syntheticFace(),
        imageSize: imageSize,
        mesh: const FaceMeshBuilder().build(syntheticFace(), imageSize),
      );
      final params = {
        for (final key in FaceFilterPipeline.faceWarpParameterKeys) key: 0.8,
      };
      final intents = AnatomicalIntentFactory.build(
        parameters: params,
        context: context,
      );

      expect(intents.length, FaceFilterPipeline.faceWarpParameterKeys.length);
      for (final intent in intents) {
        expect(intent.mode, DeformationMode.pilot);
        expect(PilotWarpDisplacement.pilotToolKeys, contains(intent.toolKey));
      }
    });

    test('B3 jaw — mandíbula move, lábios rígidos', () {
      final field = engine.composeVertexField(
        parameters: const {'jaw': 1.0},
        context: _context(),
      );
      expect(
        field.maxDisplacementInIndices(VertexRoleMap.jawLeft),
        greaterThan(1.0),
      );
      expect(
        field.maxDisplacementInIndices(VertexRoleMap.upperLip),
        lessThan(0.5),
      );
    });

    test('B4 chin — queixo sobe', () {
      final field = engine.composeVertexField(
        parameters: const {'chin': 1.0},
        context: _context(),
      );
      expect(
        field.maxDisplacementInIndices(VertexRoleMap.chin),
        greaterThan(1.0),
      );
      final tip = field.displacementAt(152);
      expect(tip.dy, lessThan(-0.5));
    });

    test('narrow_face — bochechas entram', () {
      final field = engine.composeVertexField(
        parameters: const {'narrow_face': 1.0},
        context: _context(),
      );
      expect(
        field.maxDisplacementInIndices(VertexRoleMap.cheekLeft),
        greaterThan(1.0),
      );
    });

    test('nose_length — nariz desce', () {
      final field = engine.composeVertexField(
        parameters: const {'nose_length': 1.0},
        context: _context(),
      );
      expect(field.displacementAt(1).dy, greaterThan(1.0));
    });

    test('direct mesh field uses v3_direct pass id', () {
      final face = syntheticFace();
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final field = engine.composeWarpField(
        face: face,
        mesh: mesh,
        imageSize: imageSize,
        parameters: const {'jaw': 1.0},
        interactivePreview: false,
      );
      expect(field, isNotNull);
      expect(field!.passId, 'face_mesh_v3_direct');
      expect(field.gridWidth, greaterThanOrEqualTo(120));
    });
  });
}

FaceAnatomyContext _context() {
  const imageSize = Size(640, 960);
  final face = syntheticFace();
  return FaceAnatomyContext(
    face: face,
    imageSize: imageSize,
    mesh: const FaceMeshBuilder().build(face, imageSize),
  );
}
