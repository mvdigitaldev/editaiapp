import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/config/face_warp_v3_config.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/face_filter_pipeline.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/face_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/pass_warp.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_mesh_deformation_engine.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/warp_cpu_remap.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/warp_field_builder.dart';
import 'package:flutter_test/flutter_test.dart';

import '../filters/skin/skin_face_fixture.dart';

import '../filters/skin/skin_face_fixture.dart';

void main() {
  const imageSize = Size(540, 720);
  const engine = FaceMeshDeformationEngine();

  setUp(() {
    FaceWarpV3Config.useGpuPiecewiseAffine = false;
    FaceWarpV3Config.useDirectMeshRender = true;
  });

  test('MLS face_slim CPU remap changes pixels (control)', () {
    final face = syntheticFace();
    final mesh = const FaceMeshBuilder().build(face, imageSize);
    const w = 540;
    const h = 720;
    final field = FaceFilterPipeline(
      fieldBuilder: WarpFieldBuilder.forFaceWarpInteractive(imageSize),
    ).compose(
      mesh: mesh,
      face: face,
      imageSize: imageSize,
      parameters: const {'face_slim': 0.99},
      unified: true,
    );
    expect(field.isIdentity, isFalse);

    final rgba = _gradientRgba(w, h);
    final out = const WarpCpuRemap(antiGhosting: false).apply(
      rgba: rgba,
      width: w,
      height: h,
      field: field,
    );
    expect(PassWarp.warpChangedPixels(rgba, out), isTrue);
  });

  test('V3 face_slim preview spreads field and remaps pixels', () {
    final face = syntheticFace();
    final mesh = const FaceMeshBuilder().build(face, imageSize);
    final field = engine.composeWarpField(
      face: face,
      mesh: mesh,
      imageSize: imageSize,
      parameters: const {'face_slim': 0.99},
      interactivePreview: true,
    );

    expect(field, isNotNull);
    expect(field!.isIdentity, isFalse);
    expect(field.passId, 'face_mesh_v3');
    // Contorno lateral tem Δv horizontal; centro protegido (nariz/olhos).
    expect(field.maxDisplacementMagnitude, greaterThan(4.0));
    expect(
      field.sampleDisplacement(const Offset(0.68, 0.50)).dx.abs(),
      greaterThan(0.25),
    );

    const w = 540;
    const h = 720;
    final rgba = _gradientRgba(w, h);
    final out = const WarpCpuRemap(antiGhosting: false).apply(
      rgba: rgba,
      width: w,
      height: h,
      field: field,
    );

    expect(identical(rgba, out), isFalse);

    final outerSample = const Offset(0.68, 0.50);
    final outerPx = (outerSample.dx * w).round();
    final outerPy = (outerSample.dy * h).round();
    final outerIdx = (outerPy * w + outerPx) * 4;
    expect(
      rgba[outerIdx] != out[outerIdx] ||
          rgba[outerIdx + 1] != out[outerIdx + 1],
      isTrue,
    );

    expect(PassWarp.warpChangedPixels(rgba, out, minAccumDiff: 500), isTrue);

    var diffInside = 0;
    for (var y = 200; y < 520; y++) {
      for (var x = 150; x < 390; x++) {
        final idx = (y * w + x) * 4;
        if (rgba[idx] != out[idx] || rgba[idx + 1] != out[idx + 1]) {
          diffInside++;
        }
      }
    }
    expect(diffInside, greaterThan(500));
  });
}

Uint8List _gradientRgba(int w, int h) {
  final rgba = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final o = (y * w + x) * 4;
      rgba[o] = x % 256;
      rgba[o + 1] = y % 256;
      rgba[o + 2] = ((x + y) % 256);
      rgba[o + 3] = 255;
    }
  }
  return rgba;
}
