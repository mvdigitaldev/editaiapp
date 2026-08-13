import 'dart:convert';
import 'dart:io';

import 'package:editaiapp/features/editor/beauty_engine/mesh/face_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_warp_mvp_calibration_diagnostic.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_warp_mvp_structural_validation_diagnostic.dart';
import 'package:flutter_test/flutter_test.dart';

import '../filters/skin/mvp_benchmark_faces.dart';

/// Etapa 4 — validação sintético vs real (sem calibração nova).
///
/// Pré-requisito: export_benchmark_landmarks_main.dart (5 fotos reais).
/// flutter test test/beauty_engine/warp/mvp_calibration_stage4_validation_test.dart
void main() {
  const tools = [
    'cheekbone',
    'v_face',
    'narrow_face',
    'forehead',
    'chin',
    'jaw',
  ];
  final outDir = '${Directory.current.path}/.cursor/mvp-calibration-stage4';

  test('Stage 4 — synthetic vs real benchmark validation', () async {
    final synthetic = defaultSyntheticBenchmarkFaces()
        .map(
          (s) => (
            id: s.id,
            label: s.label ?? s.shape.name,
            face: syntheticFaceForShape(s.shape),
            imageSize: s.imageSize,
            isSynthetic: true,
          ),
        )
        .toList();
    final real = loadAvailableRealBenchmarkFaces()
        .map(
          (r) => (
            id: r.id,
            label: r.label,
            face: r.face,
            imageSize: r.imageSize,
            isSynthetic: false,
          ),
        )
        .toList();

    expect(synthetic.length, greaterThanOrEqualTo(5));
    expect(real.length, greaterThanOrEqualTo(5), reason: 'run export first');

    final allFaces = [...synthetic, ...real];
    const builder = FaceMeshBuilder();
    Directory(outDir).createSync(recursive: true);

    final toolReports = <Map<String, dynamic>>[];
    var structuralPassAll = true;

    for (final toolKey in tools) {
      final synMetrics = <Map<String, dynamic>>[];
      final realMetrics = <Map<String, dynamic>>[];

      for (final f in allFaces) {
        final mesh = builder.build(f.face, f.imageSize);
        final summary = await FaceWarpMvpCalibrationDiagnostic.run(
          face: f.face,
          mesh: mesh,
          imageSize: f.imageSize,
          toolKeysFilter: [toolKey],
          writeHeatmaps: false,
          runId: 'stage4-$toolKey-${f.id}',
        );

        final toolReport = (summary['tools'] as List)
            .cast<Map<String, dynamic>>()
            .firstWhere((t) => t['toolKey'] == toolKey);
        final ref = summary['faceSlimReferenceEffectiveRoiMaxPx'] as double;
        final at100 = (toolReport['intensityReports'] as List).last
            as Map<String, dynamic>;
        final eff = at100['effective'] as Map<String, dynamic>;

        final row = {
          'id': f.id,
          'label': f.label,
          'isSynthetic': f.isSynthetic,
          'faceSlimRefPx': ref,
          'effectiveRoiMaxPx': eff['roiMaxDisplacementPx'],
          'effectiveRoiMeanPx': eff['roiMeanDisplacementPx'],
          'roiMovedVertexCount': eff['roiMovedVertexCount'],
          'gapVsFaceSlimPct':
              ref > 0 ? 1.0 - (eff['roiMaxDisplacementPx'] as num) / ref : 0.0,
          'aceRetentionFromGenerator': at100['aceRetentionFromGenerator'],
          'phase9RetentionFromAce': at100['phase9RetentionFromAce'],
          'effectiveRetentionFromPhase9': at100['effectiveRetentionFromPhase9'],
          'primaryBottleneck': toolReport['primaryBottleneck'],
        };

        if (f.isSynthetic) {
          synMetrics.add(row);
        } else {
          realMetrics.add(row);
        }

        final structural =
            FaceWarpMvpStructuralValidationDiagnostic.validateTool(
          toolKey: toolKey,
          face: f.face,
          mesh: mesh,
          imageSize: f.imageSize,
          skipFieldDiagnostics: true,
        );
        if (structural['structuralPassAllIntensities'] != true) {
          structuralPassAll = false;
        }
      }

      double avg(List<Map<String, dynamic>> rows, String key) {
        if (rows.isEmpty) {
          return 0;
        }
        return rows
                .map((r) => (r[key] as num).toDouble())
                .reduce((a, b) => a + b) /
            rows.length;
      }

      String dominantBottleneck(List<Map<String, dynamic>> rows) {
        final counts = <String, int>{};
        for (final r in rows) {
          final b = r['primaryBottleneck'] as String;
          counts[b] = (counts[b] ?? 0) + 1;
        }
        return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      }

      final synGap = avg(synMetrics, 'gapVsFaceSlimPct');
      final realGap = avg(realMetrics, 'gapVsFaceSlimPct');
      final synBn = dominantBottleneck(synMetrics);
      final realBn = dominantBottleneck(realMetrics);

      toolReports.add({
        'toolKey': toolKey,
        'synthetic': {
          'faceCount': synMetrics.length,
          'avgEffectiveRoiMaxPx': avg(synMetrics, 'effectiveRoiMaxPx'),
          'avgEffectiveRoiMeanPx': avg(synMetrics, 'effectiveRoiMeanPx'),
          'avgRoiMovedVertexCount': avg(synMetrics, 'roiMovedVertexCount'),
          'avgAceRetentionFromGenerator':
              avg(synMetrics, 'aceRetentionFromGenerator'),
          'avgEffectiveRetentionFromPhase9':
              avg(synMetrics, 'effectiveRetentionFromPhase9'),
          'avgGapVsFaceSlimPct': synGap,
          'dominantBottleneck': synBn,
          'perFace': synMetrics,
        },
        'real': {
          'faceCount': realMetrics.length,
          'avgEffectiveRoiMaxPx': avg(realMetrics, 'effectiveRoiMaxPx'),
          'avgEffectiveRoiMeanPx': avg(realMetrics, 'effectiveRoiMeanPx'),
          'avgRoiMovedVertexCount': avg(realMetrics, 'roiMovedVertexCount'),
          'avgAceRetentionFromGenerator':
              avg(realMetrics, 'aceRetentionFromGenerator'),
          'avgEffectiveRetentionFromPhase9':
              avg(realMetrics, 'effectiveRetentionFromPhase9'),
          'avgGapVsFaceSlimPct': realGap,
          'dominantBottleneck': realBn,
          'perFace': realMetrics,
        },
        'gapDifferencePctPoints': (realGap - synGap) * 100,
        'sameBottleneck': synBn == realBn,
      });
    }

    final report = {
      'phase': 4,
      'syntheticFaceCount': synthetic.length,
      'realFaceCount': real.length,
      'structuralPassAllToolsAndFaces': structuralPassAll,
      'tools': toolReports,
    };

    File('$outDir/stage4-validation-report.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(report),
    );
    File('$outDir/stage4-validation-report.md').writeAsStringSync(
      _markdown(report),
    );

    // ignore: avoid_print
    print('STAGE4 structuralPassAll=$structuralPassAll');
    for (final t in toolReports) {
      final syn = t['synthetic'] as Map<String, dynamic>;
      final real = t['real'] as Map<String, dynamic>;
      // ignore: avoid_print
      print(
        'STAGE4 ${t['toolKey']}: synGap=${((syn['avgGapVsFaceSlimPct'] as double) * 100).toStringAsFixed(0)}% '
        'realGap=${((real['avgGapVsFaceSlimPct'] as double) * 100).toStringAsFixed(0)}% '
        'sameBn=${t['sameBottleneck']} syn=${syn['dominantBottleneck']} real=${real['dominantBottleneck']}',
      );
    }

    expect(structuralPassAll, isTrue);
  });
}

String _markdown(Map<String, dynamic> report) {
  final buf = StringBuffer()
    ..writeln('# Stage 4 — Validação sintético vs real')
    ..writeln()
    ..writeln(
      'Structural PASS all: ${report['structuralPassAllToolsAndFaces']}',
    )
    ..writeln()
    ..writeln(
      '| Tool | Synthetic Gap | Real Gap | Diferença (pp) | Mesmo gargalo? |',
    )
    ..writeln('|------|---------------|----------|----------------|----------------|');

  for (final t in (report['tools'] as List).cast<Map<String, dynamic>>()) {
    final syn = t['synthetic'] as Map<String, dynamic>;
    final real = t['real'] as Map<String, dynamic>;
    buf.writeln(
      '| ${t['toolKey']} '
      '| ${((syn['avgGapVsFaceSlimPct'] as num) * 100).toStringAsFixed(0)}% '
      '| ${((real['avgGapVsFaceSlimPct'] as num) * 100).toStringAsFixed(0)}% '
      '| ${(t['gapDifferencePctPoints'] as num).toStringAsFixed(1)} '
      '| ${t['sameBottleneck'] == true ? 'SIM' : 'NÃO'} |',
    );
  }

  return buf.toString();
}
