import 'dart:io';
import 'dart:typed_data';

import 'package:editaiapp/features/editor/beauty_engine/warp/face_warp_mvp_visual_validation.dart';
import 'package:flutter/material.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../filters/skin/mvp_benchmark_faces.dart';

List<FaceBenchInput> _loadBenchmarkFaces() {
  final out = <FaceBenchInput>[];
  for (final spec in defaultSyntheticBenchmarkFaces()) {
    final face = syntheticFaceForShape(spec.shape);
    out.add(FaceBenchInput(
      id: spec.id,
      label: spec.label ?? spec.shape.name,
      face: face,
      imageSize: spec.imageSize,
      sourceRgba: FaceWarpMvpVisualValidation.syntheticPortraitRgba(
        face,
        spec.imageSize,
      ),
      isSynthetic: true,
    ));
  }
  for (final r in loadAvailableRealBenchmarkFaces()) {
    final asset = FaceWarpMvpVisualValidation.realPhotoAssets[r.id];
    if (asset == null || !File(asset).existsSync()) {
      continue;
    }
    final decoded = img.decodeImage(File(asset).readAsBytesSync());
    if (decoded == null) {
      continue;
    }
    final rgba = Uint8List(decoded.width * decoded.height * 4);
    var o = 0;
    for (var y = 0; y < decoded.height; y++) {
      for (var x = 0; x < decoded.width; x++) {
        final p = decoded.getPixel(x, y);
        rgba[o++] = p.r.toInt();
        rgba[o++] = p.g.toInt();
        rgba[o++] = p.b.toInt();
        rgba[o++] = p.a.toInt();
      }
    }
    out.add(FaceBenchInput(
      id: r.id,
      label: r.label,
      face: r.face,
      imageSize: r.imageSize,
      sourceRgba: rgba,
      isSynthetic: false,
    ));
  }
  return out;
}

void main() {
  test('Stage 6.3 — visual validation 120 renders', () async {
    final faces = _loadBenchmarkFaces();
    expect(faces.length, greaterThanOrEqualTo(10));

    final outDir =
        '${Directory.current.path}/.cursor/mvp-calibration-stage6/stage6-3-visual';

    final report = await FaceWarpMvpVisualValidation.run(
      outputDirectory: outDir,
      faces: faces,
    );

    expect(report['renderCount'], 120);
    expect((report['verdict'] as Map)['decision'], isNotNull);

    // ignore: avoid_print
    print('STAGE6.3 verdict=${(report['verdict'] as Map)['decision']}');
    for (final t in (report['tools'] as List).cast<Map<String, dynamic>>()) {
      final agg = t['aggregateRecVsSecond'] as Map<String, dynamic>;
      final worse = (t['perFace'] as List)
          .where((f) => (f as Map)['recWorseThanSecond'] == true)
          .length;
      // ignore: avoid_print
      print(
        'STAGE6.3 ${t['toolKey']}: ssimRecVs2nd=${(agg['avgSsimRecVsSecond'] as num).toStringAsFixed(4)} '
        'recWorseThan2nd=$worse/10 outliers=${(t['outliers'] as List).length}',
      );
    }
  });
}
