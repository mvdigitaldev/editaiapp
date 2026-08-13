import 'dart:io';
import 'dart:typed_data';

import 'package:editaiapp/features/editor/beauty_engine/mesh/face_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_warp_fse_compression_audit.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_warp_geometry_perception_audit.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_warp_mvp_visual_validation.dart';
import 'package:flutter/material.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../filters/skin/mvp_benchmark_faces.dart';

List<FseAuditFaceInput> _loadFaces({bool allReal = true}) {
  const builder = FaceMeshBuilder();
  final out = <FseAuditFaceInput>[];

  for (final spec in defaultSyntheticBenchmarkFaces()) {
    final face = syntheticFaceForShape(spec.shape);
    out.add(FseAuditFaceInput(
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
    out.add(FseAuditFaceInput(
      id: r.id,
      face: r.face,
      mesh: builder.build(r.face, r.imageSize),
      imageSize: r.imageSize,
      sourceRgba: rgba,
    ));
  }

  return out;
}

/// flutter test test/beauty_engine/warp/geometry_perception_audit_test.dart
void main() {
  test('Geometry perception audit — ROI, weights, sensitivity', () async {
    final allFaces = _loadFaces();
    expect(allFaces.length, greaterThanOrEqualTo(5));

    // Renders: 1 sintético (oval). Análise de ROI/pesos: todos os rostos.
    final renderFaces = allFaces.where((f) => f.id == 'syn-oval').take(1).toList();

    final outDir = '${Directory.current.path}/.cursor/geometry-perception-audit';
    final report = await FaceWarpGeometryPerceptionAudit.run(
      analysisFaces: allFaces,
      renderFaces: renderFaces,
      outputDirectory: outDir,
    );

    expect(File('$outDir/geometry-perception-audit.json').existsSync(), isTrue);

    for (final tool in report['tools'] as List) {
      final key = tool['toolKey'] as String;
      final agg = tool['aggregateRoi'] as Map<String, dynamic>;
      // ignore: avoid_print
      print(
        'GEOM $key verts=${agg['avgAnalysisVertices']} sig>1px=${agg['avgSignificantAbove1px']} '
        'edge=${agg['avgEdgeWeight']} support=${agg['avgSupportWeight']}',
      );
      for (final r in tool['bottleneckRanking'] as List) {
        // ignore: avoid_print
        print('  #${r['rank']} ${r['parameter']} @30%=${r['estimatedVisualGainAt30pct']}%');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 30)));
}
