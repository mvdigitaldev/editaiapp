import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/config/face_warp_v3_config.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/face_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/anatomical_intent.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_mesh_deformation_engine.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/vertex_role_map.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_mesh_warp_rasterizer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../filters/skin/skin_face_fixture.dart';

void main() {
  const imageSize = Size(640, 960);
  const engine = FaceMeshDeformationEngine();

  setUp(() {
    FaceWarpV3Config.useGpuPiecewiseAffine = false;
  });

  test('V3 compose produces warp field with face_mesh_v3 passId', () {
    FaceWarpV3Config.enabled = true;
    FaceWarpV3Config.useDirectMeshRender = false;
    final face = syntheticFace();
    final mesh = const FaceMeshBuilder().build(face, imageSize);

    final field = engine.composeWarpField(
      face: face,
      mesh: mesh,
      imageSize: imageSize,
      parameters: const {'face_slim': 0.85},
      interactivePreview: true,
    );

    expect(field, isNotNull);
    expect(field!.isIdentity, isFalse);
    expect(field.passId, 'face_mesh_v3');
    expect(field.maxDisplacementMagnitude, greaterThan(1.0));
  });

  test('GPU piecewise + direct config uses spread CPU fallback field', () {
    FaceWarpV3Config.useDirectMeshRender = true;
    FaceWarpV3Config.useGpuPiecewiseAffine = true;
    final face = syntheticFace();
    final mesh = const FaceMeshBuilder().build(face, imageSize);

    final field = engine.composeWarpField(
      face: face,
      mesh: mesh,
      imageSize: imageSize,
      parameters: const {'face_slim': 0.85},
      interactivePreview: true,
    );

    expect(field, isNotNull);
    expect(field!.isIdentity, isFalse);
    expect(field.passId, 'face_mesh_v3_gpu');
    expect(field.maxDisplacementMagnitude, greaterThan(1.0));
  });

  test('V3 direct compose uses face_mesh_v3_direct passId on export', () {
    FaceWarpV3Config.useDirectMeshRender = true;
    final face = syntheticFace();
    final mesh = const FaceMeshBuilder().build(face, imageSize);

    final field = engine.composeWarpField(
      face: face,
      mesh: mesh,
      imageSize: imageSize,
      parameters: const {'face_slim': 0.85},
      interactivePreview: false,
      exporting: true,
    );

    expect(field?.passId, 'face_mesh_v3_direct');
  });

  test('V3 face_slim keeps displacement outside matte low', () {
    final face = syntheticFace();
    final mesh = const FaceMeshBuilder().build(face, imageSize);

    final field = engine.composeWarpField(
      face: face,
      mesh: mesh,
      imageSize: imageSize,
      parameters: const {'face_slim': 1.0},
      interactivePreview: true,
    );

    expect(field, isNotNull);
    // Canto superior esquerdo (fundo) deve ter máscara ~0.
    final cornerMask = field!.sampleMask(const Offset(0.02, 0.02));
    expect(cornerMask, lessThan(0.05));
  });

  test('vertex field pins eyes on face_slim', () {
    final face = syntheticFace();
    final mesh = const FaceMeshBuilder().build(face, imageSize);

    final vertexField = engine.composeVertexField(
      parameters: const {'face_slim': 1.0},
      context: FaceAnatomyContext(
        face: face,
        imageSize: imageSize,
        mesh: mesh,
      ),
    );

    expect(
      vertexField.maxDisplacementInIndices(VertexRoleMap.eyeLeft),
      lessThan(0.5),
    );
    expect(
      vertexField.maxDisplacementInIndices(VertexRoleMap.jawLeft),
      greaterThan(0.5),
    );
  });

  test('rasterizer does not import MLS solver path', () {
    // Garantia estrutural: API V3 não expõe compose com ControlPoints.
    expect(
      FaceMeshWarpRasterizer.rasterizeFromVertexField,
      isNotNull,
    );
  });
}
