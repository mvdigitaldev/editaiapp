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

/// Goldens V3 olhos + boca (Sprint 35) — remap CPU determinístico.
void main() {
  const width = 256;
  const height = 320;
  const imageSize = Size(width * 1.0, height * 1.0);
  const engine = FaceMeshDeformationEngine();

  setUpAll(() {
    FaceWarpV3Config.enabled = true;
  });

  Uint8List renderPilot({
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
    expect(field, isNotNull, reason: '$parameterKey deve produzir warp V3');
    return const WarpCpuRemap().apply(
      rgba: syntheticPortrait(width, height),
      width: width,
      height: height,
      field: field!,
    );
  }

  group('V3 eye/mouth goldens', () {
    test('eye_distance B5 at max', () {
      expectMatchesGolden(
        name: 'v3_eye_distance',
        rgba: renderPilot(parameterKey: 'eye_distance', intensity: 1.0),
        width: width,
        height: height,
      );
    });

    test('lip_thickness B6 at max', () {
      expectMatchesGolden(
        name: 'v3_lip_thickness',
        rgba: renderPilot(parameterKey: 'lip_thickness', intensity: 1.0),
        width: width,
        height: height,
      );
    });

    test('smile at max', () {
      expectMatchesGolden(
        name: 'v3_smile',
        rgba: renderPilot(parameterKey: 'smile', intensity: 1.0),
        width: width,
        height: height,
      );
    });
  });
}
