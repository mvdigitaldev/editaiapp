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

/// Goldens V3 dos 3 filtros piloto (Sprint 34) — remap CPU determinístico.
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

  group('V3 pilot goldens', () {
    test('face_slim B1 at max', () {
      expectMatchesGolden(
        name: 'v3_pilot_face_slim',
        rgba: renderPilot(parameterKey: 'face_slim', intensity: 1.0),
        width: width,
        height: height,
      );
    });

    test('nose_slim B2 at max', () {
      expectMatchesGolden(
        name: 'v3_pilot_nose_slim',
        rgba: renderPilot(parameterKey: 'nose_slim', intensity: 1.0),
        width: width,
        height: height,
      );
    });

    test('eye_scale B5 at max', () {
      expectMatchesGolden(
        name: 'v3_pilot_eye_scale',
        rgba: renderPilot(parameterKey: 'eye_scale', intensity: 1.0),
        width: width,
        height: height,
      );
    });
  });
}
