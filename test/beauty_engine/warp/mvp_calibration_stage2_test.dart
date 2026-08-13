import 'dart:io';

import 'package:editaiapp/features/editor/beauty_engine/mesh/face_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_warp_mvp_calibration_diagnostic.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_warp_mvp_calibration_stage2_benchmark.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_warp_mvp_structural_validation_diagnostic.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../filters/skin/mvp_benchmark_faces.dart';

/// Etapa 2 — calibração incremental MVP (generators only).
///
/// flutter test test/beauty_engine/warp/mvp_calibration_stage2_test.dart
void main() {
  const calibrationOrder = [
    'cheekbone',
    'v_face',
    'narrow_face',
    'forehead',
    'chin',
    'jaw',
  ];

  final outRoot = '${Directory.current.path}/.cursor/mvp-calibration-stage2';

  List<({
    String id,
    String label,
    FaceMeshResult face,
    Size imageSize,
    bool isSynthetic,
  })> buildBenchmarkFaces() {
    final faces = <({
      String id,
      String label,
      FaceMeshResult face,
      Size imageSize,
      bool isSynthetic,
    })>[];

    for (final spec in defaultSyntheticBenchmarkFaces()) {
      faces.add((
        id: spec.id,
        label: spec.label ?? spec.shape.name,
        face: syntheticFaceForShape(spec.shape),
        imageSize: spec.imageSize,
        isSynthetic: true,
      ));
    }

    for (final real in loadAvailableRealBenchmarkFaces()) {
      faces.add((
        id: real.id,
        label: real.label,
        face: real.face,
        imageSize: real.imageSize,
        isSynthetic: false,
      ));
    }

    return faces;
  }

  group('MVP calibration stage 2 — incremental', () {
    late List<
        ({
          String id,
          String label,
          FaceMeshResult face,
          Size imageSize,
          bool isSynthetic,
        })> benchmarkFaces;

    setUpAll(() async {
      benchmarkFaces = buildBenchmarkFaces();
      final syntheticCount =
          benchmarkFaces.where((f) => f.isSynthetic).length;
      final realCount = benchmarkFaces.where((f) => !f.isSynthetic).length;
      // ignore: avoid_print
      print(
        'STAGE2 benchmark faces: $syntheticCount synthetic + $realCount real '
        '(total ${benchmarkFaces.length})',
      );
      expect(syntheticCount, greaterThanOrEqualTo(5));

      // face_slim structural baseline (Phase 14 proxy) — uma vez
      const builder = FaceMeshBuilder();
      final structuralFaces = benchmarkFaces.map((f) {
        return (
          id: f.id,
          label: f.label,
          face: f.face,
          mesh: builder.build(f.face, f.imageSize),
          imageSize: f.imageSize,
          personMask: null,
        );
      }).toList();
      final faceSlimStructural =
          FaceWarpMvpStructuralValidationDiagnostic.validateBatch(
        toolKey: 'face_slim',
        faces: structuralFaces,
        outputDirectory: outRoot,
        runId: 'stage2-face_slim-baseline',
        skipFieldDiagnostics: true,
      );
      expect(faceSlimStructural['structuralPassAllFaces'], isTrue);
    });

    for (final toolKey in calibrationOrder) {
      test('$toolKey — benchmark + structural PASS', () async {
        final report = await FaceWarpMvpCalibrationStage2Benchmark
            .runToolCalibration(
          toolKey: toolKey,
          faces: benchmarkFaces,
          outputDirectory: '$outRoot/$toolKey',
          runId: 'stage2-$toolKey',
          validateFaceSlimStructural: false,
        );

        expect(report['phase14ProxyPass'], isTrue, reason: toolKey);

        final agg = report['aggregate'] as Map<String, dynamic>;
        final maxRoi = agg['avgEffectiveRoiMaxPx'] as double;
        final meanRoi = agg['avgEffectiveRoiMeanPx'] as double;
        final verts = agg['avgRoiMovedVertexCount'] as double;
        final gap = agg['avgGapVsFaceSlimPct'] as double;

        // ignore: avoid_print
        print(
          'STAGE2 $toolKey: maxROI=${maxRoi.toStringAsFixed(2)} '
          'meanROI=${meanRoi.toStringAsFixed(2)} verts=${verts.toStringAsFixed(1)} '
          'gap=${(gap * 100).toStringAsFixed(0)}% P14=${report['phase14ProxyPass']}',
        );

        final synOval = benchmarkFaces.firstWhere((f) => f.id == 'syn-oval');
        const builder = FaceMeshBuilder();
        final mesh = builder.build(synOval.face, synOval.imageSize);
        final stage1 = await FaceWarpMvpCalibrationDiagnostic.run(
          face: synOval.face,
          mesh: mesh,
          imageSize: synOval.imageSize,
          outputDirectory: '$outRoot/$toolKey/syn-oval-detail',
          runId: 'detail-$toolKey',
        );
        final toolReport = (stage1['tools'] as List)
            .cast<Map<String, dynamic>>()
            .firstWhere((t) => t['toolKey'] == toolKey);
        final intensities = FaceWarpMvpCalibrationDiagnostic.defaultIntensities;
        final curveParts = <String>[];
        for (var i = 0; i < intensities.length; i++) {
          final r = (toolReport['intensityReports'] as List)[i] as Map;
          final eff = r['effective'] as Map;
          curveParts.add(
            '${intensities[i]}→${(eff['roiMaxDisplacementPx'] as num).toStringAsFixed(1)}',
          );
        }
        // ignore: avoid_print
        print('STAGE2 $toolKey slider syn-oval: ${curveParts.join(' | ')}');

        if (toolKey == 'forehead') {
          final supportLoss =
              FaceWarpMvpCalibrationDiagnostic.measureGeometricSupportLoss(
            toolKey: toolKey,
            face: synOval.face,
            mesh: mesh,
            imageSize: synOval.imageSize,
          );
          File('$outRoot/$toolKey/forehead-support-loss.json').writeAsStringSync(
            supportLoss.toString(),
          );
          // ignore: avoid_print
          print(
            'STAGE2 forehead Support: max loss '
            '${(supportLoss['roiMaxLossPct'] as num).toStringAsFixed(1)}% '
            'verts ${supportLoss['roiMovedBeforeSupport']}→'
            '${supportLoss['roiMovedAfterSupport']}',
          );
          for (final v in (supportLoss['perVertex'] as List).take(5)) {
            final m = v as Map<String, dynamic>;
            // ignore: avoid_print
            print(
              '  vtx ${m['index']}: P9=${(m['phase9MagPx'] as num).toStringAsFixed(2)} '
              '→ eff=${(m['effectiveMagPx'] as num).toStringAsFixed(2)} '
              'loss=${(m['lossPct'] as num).toStringAsFixed(1)}% '
              'w=${(m['supportWeight'] as num).toStringAsFixed(2)}',
            );
          }
          expect(supportLoss['roiMovedBeforeSupport'], greaterThanOrEqualTo(7));
        }

        expect(maxRoi, greaterThan(0));
        expect(meanRoi, greaterThan(0));
        expect(verts, greaterThan(0));
      });
    }
  });
}
