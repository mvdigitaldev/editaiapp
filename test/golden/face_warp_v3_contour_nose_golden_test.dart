import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/config/face_warp_v3_config.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/face_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_mesh_deformation_engine.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/warp_cpu_remap.dart';
import 'package:flutter_test/flutter_test.dart';

import '../beauty_engine/filters/skin/skin_face_fixture.dart';
import 'golden_test_utils.dart';
import 'synthetic_portrait.dart';

/// Goldens V3 Sprint 36 — contorno + nariz.
void main() {
  const width = 256;
  const height = 320;
  const imageSize = Size(width * 1.0, height * 1.0);
  const engine = FaceMeshDeformationEngine();

  setUpAll(() {
    FaceWarpV3Config.enabled = true;
    FaceWarpV3Config.useDirectMeshRender = true;
  });

  Uint8List render({
    required String parameterKey,
    required double intensity,
  }) {
    final face = syntheticFace();
    final mesh = const FaceMeshBuilder().build(face, imageSize);
    final field = engine.composeWarpField(
      face: face,
      mesh: mesh,
      imageSize: imageSize,
      parameters: {parameterKey: intensity},
      interactivePreview: false,
    );
    expect(field, isNotNull, reason: '$parameterKey deve produzir warp V3 direct');
    return const WarpCpuRemap().apply(
      rgba: syntheticPortrait(width, height),
      width: width,
      height: height,
      field: field!,
    );
  }

  group('V3 contour/nose goldens', () {
    test('jaw B3 at max', () {
      expectMatchesGolden(
        name: 'v3_jaw',
        rgba: render(parameterKey: 'jaw', intensity: 1.0),
        width: width,
        height: height,
      );
    });

    test('chin B4 at max', () {
      expectMatchesGolden(
        name: 'v3_chin',
        rgba: render(parameterKey: 'chin', intensity: 1.0),
        width: width,
        height: height,
      );
    });

    test('narrow_face at max', () {
      expectMatchesGolden(
        name: 'v3_narrow_face',
        rgba: render(parameterKey: 'narrow_face', intensity: 1.0),
        width: width,
        height: height,
      );
    });

    test('nose_length at max', () {
      expectMatchesGolden(
        name: 'v3_nose_length',
        rgba: render(parameterKey: 'nose_length', intensity: 1.0),
        width: width,
        height: height,
      );
    });
  });
}
