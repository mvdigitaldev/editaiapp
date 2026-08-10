import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/mesh/face_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/anatomical_intent.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/constrained_vertex_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_mesh_deformation_engine.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_warp_vacancy_fill.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/vertex_role_map.dart';
import 'package:flutter_test/flutter_test.dart';

import '../filters/skin/skin_face_fixture.dart';

/// Regressão B1 — invariantes mensuráveis de `face_slim`
/// (ver `docs/beauty/13-visual-quality-targets.md` § B1).
void main() {
  const imageSize = Size(640, 960);
  const engine = FaceMeshDeformationEngine();

  ConstrainedVertexField fieldAt(double intensity) {
    final face = syntheticFace();
    final mesh = const FaceMeshBuilder().build(face, imageSize);
    return engine.composeVertexField(
      parameters: {'face_slim': intensity},
      context: FaceAnatomyContext(
        face: face,
        imageSize: imageSize,
        mesh: mesh,
      ),
    );
  }

  group('B1 face_slim quality invariants', () {
    test('eyes and nose immobile at 100%', () {
      final field = fieldAt(1.0);

      expect(
        field.maxDisplacementInIndices(VertexRoleMap.eyeLeft),
        lessThan(0.5),
        reason: 'B1: olho esquerdo imóvel',
      );
      expect(
        field.maxDisplacementInIndices(VertexRoleMap.eyeRight),
        lessThan(0.5),
        reason: 'B1: olho direito imóvel',
      );
      expect(
        field.maxDisplacementInIndices(VertexRoleMap.noseTip),
        lessThan(0.5),
        reason: 'B1: ponta do nariz imóvel',
      );
      expect(
        field.maxDisplacementInIndices(VertexRoleMap.noseAlae),
        lessThan(0.5),
        reason: 'B1: asas do nariz imóveis',
      );
    });

    test('mouth and brow immobile at 100%', () {
      final field = fieldAt(1.0);

      expect(
        field.maxDisplacementInIndices(VertexRoleMap.upperLip),
        lessThan(0.5),
      );
      expect(
        field.maxDisplacementInIndices(VertexRoleMap.lowerLip),
        lessThan(0.5),
      );
      expect(
        field.maxDisplacementInIndices(VertexRoleMap.browLeft),
        lessThan(0.5),
      );
      expect(
        field.maxDisplacementInIndices(VertexRoleMap.browRight),
        lessThan(0.5),
      );
    });

    test('jaw moves inward symmetrically', () {
      final field = fieldAt(1.0);

      final jawL = field.maxDisplacementInIndices(VertexRoleMap.jawLeft);
      final jawR = field.maxDisplacementInIndices(VertexRoleMap.jawRight);
      expect(jawL, greaterThan(2.0));
      expect(jawR, greaterThan(2.0));
      expect((jawL - jawR).abs(), lessThan(jawL * 0.15 + 0.5),
          reason: 'B1: simetria mandíbula');
    });

    test('displacement scales with slider intensity', () {
      final low = fieldAt(0.3);
      final high = fieldAt(1.0);
      expect(
        high.maxDisplacementInIndices(VertexRoleMap.jawLeft),
        greaterThan(
          low.maxDisplacementInIndices(VertexRoleMap.jawLeft),
        ),
      );
    });

    test('vacancy fill disabled for face_slim on grid', () {
      expect(
        FaceWarpVacancyFill.vacancySourceIndices(const {'face_slim': 0.9}),
        isEmpty,
      );
    });

    test('vacancy fill limited to eyes for eye_distance', () {
      final indices = FaceWarpVacancyFill.vacancySourceIndices(
        const {'eye_distance': 0.5},
      );
      expect(indices, isNotEmpty);
      expect(indices.contains(VertexRoleMap.jawLeft.first), isFalse);
      expect(indices.contains(VertexRoleMap.eyeLeft.first), isTrue);
    });
  });
}
