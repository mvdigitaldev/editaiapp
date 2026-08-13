import 'dart:io';
import 'dart:typed_data';

import 'package:editaiapp/features/editor/beauty_engine/mesh/face_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_warp_fse_compression_audit.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_warp_mvp_visual_validation.dart';
import 'package:flutter/material.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../filters/skin/mvp_benchmark_faces.dart';

/// flutter test test/beauty_engine/warp/fse_compression_audit_test.dart
void main() {
  test('FSE compression audit — chin, cheekbone, narrow_face', () async {
    const builder = FaceMeshBuilder();
    const imageSize = Size(640, 960);
    final outDir = '${Directory.current.path}/.cursor/fse-compression-audit';
    final inputs = <FseAuditFaceInput>[];

    for (final spec in defaultSyntheticBenchmarkFaces()) {
      final face = syntheticFaceForShape(spec.shape);
      inputs.add(FseAuditFaceInput(
        id: spec.id,
        face: face,
        mesh: builder.build(face, spec.imageSize),
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
      inputs.add(FseAuditFaceInput(
        id: r.id,
        face: r.face,
        mesh: builder.build(r.face, r.imageSize),
        imageSize: r.imageSize,
        sourceRgba: rgba,
      ));
    }

    expect(inputs.length, greaterThanOrEqualTo(5));

    final report = await FaceWarpFseCompressionAudit.run(
      faces: inputs,
      outputDirectory: outDir,
    );

    expect(File('$outDir/fse-compression-audit.json').existsSync(), isTrue);

    for (final tool in report['tools'] as List) {
      final key = tool['toolKey'] as String;
      final row = tool['summaryRow'] as Map<String, dynamic>;
      // ignore: avoid_print
      print(
        'FSE_AUDIT $key internal=+${row['internalGainPct']}% '
        'gen=+${row['generatorGainPct']}% p9=+${row['phase9GainPct']}% '
        'render=${row['perceptualRoiGainPct']}% '
        'slider=${row['flatSliderFaces']} '
        '→ ${row['verdict']}',
      );
    }
  });
}
