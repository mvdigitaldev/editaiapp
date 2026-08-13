import 'dart:io';

import 'package:editaiapp/features/editor/beauty_engine/mesh/face_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_warp_mvp_calibration_diagnostic.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../filters/skin/skin_face_fixture.dart';

/// Etapa 1 — diagnóstico MVP (synthetic face, sem alterar produção).
///
/// flutter test test/beauty_engine/warp/mvp_calibration_stage1_test.dart
void main() {
  const imageSize = Size(640, 960);
  final outDir =
      '${Directory.current.path}/.cursor/mvp-calibration-stage1';

  test('MVP calibration stage 1 — metrics + heatmaps for 7 tools', () async {
    final face = syntheticFace();
    final mesh = const FaceMeshBuilder().build(face, imageSize);

    final summary = await FaceWarpMvpCalibrationDiagnostic.run(
      face: face,
      mesh: mesh,
      imageSize: imageSize,
      outputDirectory: outDir,
      runId: 'stage1-synthetic',
    );

    expect(summary['tools'], isA<List>());
    final tools = (summary['tools'] as List).cast<Map<String, dynamic>>();
    expect(tools.length, 7);

    for (final tool in tools) {
      final key = tool['toolKey'] as String;
      expect(
        FaceWarpMvpCalibrationDiagnostic.defaultIntensities.length,
        (tool['intensityReports'] as List).length,
      );
      final heatmap = tool['heatmapPath'] as String;
      expect(File(heatmap).existsSync(), isTrue, reason: 'heatmap $key');

      final reports = tool['intensityReports'] as List;
      final at100 = reports.last as Map<String, dynamic>;
      final effective = at100['effective'] as Map<String, dynamic>;
      expect(effective['movedVertexCount'], greaterThan(0), reason: key);

      // ignore: avoid_print
      print(
        'MVP_CALIB $key @1.0 effROI=${effective['roiMaxDisplacementPx']} '
        'moved=${effective['roiMovedVertexCount']} '
        'bottleneck=${tool['primaryBottleneck']}',
      );
    }

    expect(
      File('$outDir/mvp-calibration-stage1-summary.json').existsSync(),
      isTrue,
    );
    expect(
      File('$outDir/mvp-calibration-stage1-report.md').existsSync(),
      isTrue,
    );

    final ref = summary['faceSlimReferenceEffectiveRoiMaxPx'] as double;
    expect(ref, greaterThan(0));
  });
}
