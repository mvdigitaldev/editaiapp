import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart' show Size;
import 'package:editaiapp/features/editor/beauty_engine/mesh/face_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/tri_mesh.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_model_specification.dart';

import 'face_warp_mvp_calibration_diagnostic.dart';
import 'face_warp_mvp_structural_validation_diagnostic.dart';

/// Etapa 6 — sweep experimental de `maxDisplacementFse` (uma ferramenta por vez).
abstract final class FaceWarpMvpSpecSweepBenchmark {
  FaceWarpMvpSpecSweepBenchmark._();

  static const baselineMaxDisplacementFse = {
    'v_face': 0.05,
    'chin': 0.06,
    'cheekbone': 0.05,
    'narrow_face': 0.06,
  };

  static const faceSlimReferenceCap = 0.08;

  /// Spec atual + incrementos de +10% … +60%, 0.08 (ref face_slim) e passos extras até 0.10.
  static List<double> specSweepSteps(String toolKey) {
    final baseline = baselineMaxDisplacementFse[toolKey];
    if (baseline == null) {
      throw ArgumentError('unsupported toolKey: $toolKey');
    }
    final values = <double>{baseline, faceSlimReferenceCap};
    for (var pct = 10; pct <= 80; pct += 10) {
      values.add(_round4(baseline * (1 + pct / 100)));
    }
    for (var extra = 0.085; extra <= 0.10; extra += 0.005) {
      values.add(_round4(extra));
    }
    return values.where((v) => v >= baseline - 1e-9 && v <= 0.10).toList()
      ..sort();
  }

  static Future<Map<String, dynamic>> runToolSweep({
    required String toolKey,
    required List<
        ({
          String id,
          String label,
          FaceMeshResult face,
          Size imageSize,
          bool isSynthetic,
        })> faces,
    required String outputDirectory,
    String runId = 'stage6',
  }) async {
    final steps = specSweepSteps(toolKey);
    final stepReports = <Map<String, dynamic>>[];

    for (final specValue in steps) {
      FaceModelSpecification.maxDisplacementFseOverrides = {toolKey: specValue};
      try {
        stepReports.add(
          await _runSingleSpec(
            toolKey: toolKey,
            specValue: specValue,
            faces: faces,
            outputDirectory: '$outputDirectory/fse-${_fseTag(specValue)}',
            runId: '$runId-$toolKey-${_fseTag(specValue)}',
          ),
        );
      } finally {
        FaceModelSpecification.maxDisplacementFseOverrides = null;
      }
    }

    final recommendation = _recommendProductionValue(toolKey, stepReports);
    final report = {
      'phase': 6,
      'runId': runId,
      'toolKey': toolKey,
      'baselineMaxDisplacementFse': baselineMaxDisplacementFse[toolKey],
      'faceSlimReferenceCap': faceSlimReferenceCap,
      'specSteps': steps,
      'steps': stepReports,
      'recommendation': recommendation,
    };

    Directory(outputDirectory).createSync(recursive: true);
    File('$outputDirectory/stage6-$toolKey-sweep.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(report),
    );
    File('$outputDirectory/stage6-$toolKey-sweep.md').writeAsStringSync(
      _markdown(toolKey, report),
    );
    File('$outputDirectory/stage6-$toolKey-chart.svg').writeAsStringSync(
      _svgChart(toolKey, stepReports),
    );

    return report;
  }

  static Future<Map<String, dynamic>> _runSingleSpec({
    required String toolKey,
    required double specValue,
    required List<
        ({
          String id,
          String label,
          FaceMeshResult face,
          Size imageSize,
          bool isSynthetic,
        })> faces,
    required String outputDirectory,
    required String runId,
  }) async {
    const builder = FaceMeshBuilder();
    final perFace = <Map<String, dynamic>>[];
    final structuralFaces = <({
      String id,
      String label,
      FaceMeshResult face,
      TriMesh mesh,
      Size imageSize,
    })>[];

    for (final f in faces) {
      final mesh = builder.build(f.face, f.imageSize);
      structuralFaces.add((
        id: f.id,
        label: f.label,
        face: f.face,
        mesh: mesh,
        imageSize: f.imageSize,
      ));

      final summary = await FaceWarpMvpCalibrationDiagnostic.run(
        face: f.face,
        mesh: mesh,
        imageSize: f.imageSize,
        outputDirectory: f.id == 'syn-oval' ? outputDirectory : null,
        runId: '$runId-${f.id}',
        toolKeysFilter: [toolKey],
        writeHeatmaps: f.id == 'syn-oval',
      );

      final toolReport = (summary['tools'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((t) => t['toolKey'] == toolKey);
      final ref = summary['faceSlimReferenceEffectiveRoiMaxPx'] as double;
      final intensityReports =
          (toolReport['intensityReports'] as List).cast<Map<String, dynamic>>();
      final at100 = intensityReports.last;
      final eff = at100['effective'] as Map<String, dynamic>;

      final structuralAt100 = FaceWarpMvpStructuralValidationDiagnostic.validateTool(
        toolKey: toolKey,
        face: f.face,
        mesh: mesh,
        imageSize: f.imageSize,
        intensities: const [1.0],
        skipFieldDiagnostics: false,
      );
      final structuralRow = (structuralAt100['rows'] as List).first
          as Map<String, dynamic>;
      final checks = structuralRow['structuralChecks'] as Map<String, dynamic>;
      final diagnostic = structuralRow['diagnostic'] as Map<String, dynamic>;

      perFace.add({
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
        'sliderCurve': _sliderCurve(intensityReports),
        'structuralPassAt100': structuralRow['structuralPass'],
        'safetyGatePassAt100': checks['allPassed'],
        'triangleFoldCountAt100': checks['triangleFoldCount'],
        'minTriangleJAt100': checks['minTriangleJ'],
        'fieldFoldCountAt100': diagnostic['rawFieldFoldCount'] ?? 0,
        'sameTriangleFieldFoldCountAt100':
            diagnostic['sameTriangleFieldFoldCount'] ?? 0,
        'boundaryCrossingCountAt100': diagnostic['boundaryCrossingCount'] ?? 0,
        'heatmapPath': toolReport['heatmapPath'],
      });
    }

    final structural = FaceWarpMvpStructuralValidationDiagnostic.validateBatch(
      toolKey: toolKey,
      faces: structuralFaces
          .map(
            (f) => (
              id: f.id,
              label: f.label,
              face: f.face,
              mesh: f.mesh,
              imageSize: f.imageSize,
              personMask: null,
            ),
          )
          .toList(),
      outputDirectory: outputDirectory,
      runId: '$runId-structural',
      skipFieldDiagnostics: true,
    );

    final syn = perFace.where((f) => f['isSynthetic'] == true).toList();
    final real = perFace.where((f) => f['isSynthetic'] != true).toList();

    return {
      'maxDisplacementFse': specValue,
      'pctAboveBaseline': _pctAboveBaseline(toolKey, specValue),
      'aggregateAll': _aggregate(perFace),
      'aggregateSynthetic': _aggregate(syn),
      'aggregateReal': _aggregate(real),
      'perFace': perFace,
      'structuralValidation': structural,
      'structuralPassAllFaces': structural['structuralPassAllFaces'],
      'anyFieldFoldAt100': perFace.any((f) => (f['fieldFoldCountAt100'] as int) > 0),
      'anyTriangleFoldAt100':
          perFace.any((f) => (f['triangleFoldCountAt100'] as int) > 0),
      'anySafetyGateFailAt100':
          perFace.any((f) => f['safetyGatePassAt100'] != true),
      'maxFieldFoldCountAt100': perFace
          .map((f) => f['fieldFoldCountAt100'] as int)
          .fold(0, math.max),
      'regressionDetected': _detectRegression(perFace, structural),
    };
  }

  static bool _detectRegression(
    List<Map<String, dynamic>> perFace,
    Map<String, dynamic> structural,
  ) {
    if (structural['structuralPassAllFaces'] != true) {
      return true;
    }
    if (perFace.any((f) => f['safetyGatePassAt100'] != true)) {
      return true;
    }
    if (perFace.any((f) => (f['triangleFoldCountAt100'] as int) > 0)) {
      return true;
    }
    return false;
  }

  static Map<String, dynamic> _recommendProductionValue(
    String toolKey,
    List<Map<String, dynamic>> steps,
  ) {
    final passing = steps.where((s) => s['regressionDetected'] != true).toList();
    if (passing.isEmpty) {
      return {
        'recommendedMaxDisplacementFse': baselineMaxDisplacementFse[toolKey],
        'reason': 'nenhum valor passou structural + safety gate',
      };
    }
    final best = passing.reduce(
      (a, b) {
        final aMax = (a['aggregateAll'] as Map)['avgEffectiveRoiMaxPx'] as num;
        final bMax = (b['aggregateAll'] as Map)['avgEffectiveRoiMaxPx'] as num;
        if (bMax > aMax) {
          return b;
        }
        if (bMax == aMax &&
            (b['maxDisplacementFse'] as num) > (a['maxDisplacementFse'] as num)) {
          return b;
        }
        return a;
      },
    );
    final firstRegression = steps.cast<Map<String, dynamic>?>().firstWhere(
          (s) => s!['regressionDetected'] == true,
          orElse: () => null,
        );

    return {
      'recommendedMaxDisplacementFse': best['maxDisplacementFse'],
      'recommendedAvgEffectiveRoiMaxPx':
          (best['aggregateAll'] as Map)['avgEffectiveRoiMaxPx'],
      'recommendedAvgGapVsFaceSlimPct':
          (best['aggregateAll'] as Map)['avgGapVsFaceSlimPct'],
      'firstRegressionAtFse': firstRegression?['maxDisplacementFse'],
      'reason':
          'maior eff ROI max médio com structural PASS + safety gate PASS em 10 rostos',
    };
  }

  static Map<String, dynamic> _aggregate(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return {};
    }
    double sumMax = 0,
        sumMean = 0,
        sumGap = 0,
        sumAce = 0,
        sumP9 = 0,
        sumVerts = 0;
    for (final r in rows) {
      sumMax += (r['effectiveRoiMaxPx'] as num).toDouble();
      sumMean += (r['effectiveRoiMeanPx'] as num).toDouble();
      sumGap += (r['gapVsFaceSlimPct'] as num).toDouble();
      sumAce += (r['aceRetentionFromGenerator'] as num).toDouble();
      sumP9 += (r['effectiveRetentionFromPhase9'] as num).toDouble();
      sumVerts += (r['roiMovedVertexCount'] as num).toDouble();
    }
    final n = rows.length;
    return {
      'faceCount': n,
      'avgEffectiveRoiMaxPx': sumMax / n,
      'avgEffectiveRoiMeanPx': sumMean / n,
      'avgGapVsFaceSlimPct': sumGap / n,
      'avgAceRetentionFromGenerator': sumAce / n,
      'avgEffectiveRetentionFromPhase9': sumP9 / n,
      'avgRoiMovedVertexCount': sumVerts / n,
    };
  }

  static List<Map<String, dynamic>> _sliderCurve(
    List<Map<String, dynamic>> intensityReports,
  ) {
    return intensityReports.map((m) {
      final eff = m['effective'] as Map<String, dynamic>;
      return {
        'intensity': m['intensity'],
        'effectiveRoiMaxPx': eff['roiMaxDisplacementPx'],
        'effectiveRoiMeanPx': eff['roiMeanDisplacementPx'],
        'roiMovedVertexCount': eff['roiMovedVertexCount'],
        'aceRetentionFromGenerator': m['aceRetentionFromGenerator'],
        'effectiveRetentionFromPhase9': m['effectiveRetentionFromPhase9'],
      };
    }).toList();
  }

  static double _pctAboveBaseline(String toolKey, double value) {
    final baseline = baselineMaxDisplacementFse[toolKey]!;
    return ((value / baseline) - 1) * 100;
  }

  static double _round4(double v) => (v * 10000).round() / 10000;

  static String _fseTag(double v) => v.toStringAsFixed(3).replaceAll('.', 'p');

  static String _markdown(String toolKey, Map<String, dynamic> report) {
    final baseline = report['baselineMaxDisplacementFse'];
    final rec = report['recommendation'] as Map<String, dynamic>;
    final buf = StringBuffer()
      ..writeln('# Etapa 6 — Spec sweep: $toolKey')
      ..writeln()
      ..writeln('Baseline: `$baseline` · Ref face_slim: `0.08`')
      ..writeln()
      ..writeln(
        '**Recomendado:** `${rec['recommendedMaxDisplacementFse']}` — '
        '${rec['reason']}',
      )
      ..writeln()
      ..writeln(
        '| maxDisplacementFse | +% baseline | eff max (all) | eff mean | '
        'Gen→ACE | P9→Eff | verts | gap vs slim | structural | safety@1 | '
        'tri folds | field folds | regressão |',
      )
      ..writeln(
        '|-------------------|-------------|---------------|----------|'
        '---------|--------|-------|-------------|------------|----------|'
        '----------|-------------|-----------|',
      );

    for (final s in (report['steps'] as List).cast<Map<String, dynamic>>()) {
      final agg = s['aggregateAll'] as Map<String, dynamic>;
      buf.writeln(
        '| ${s['maxDisplacementFse']} '
        '| ${(s['pctAboveBaseline'] as num).toStringAsFixed(0)}% '
        '| ${(agg['avgEffectiveRoiMaxPx'] as num).toStringAsFixed(2)} '
        '| ${(agg['avgEffectiveRoiMeanPx'] as num).toStringAsFixed(2)} '
        '| ${(agg['avgAceRetentionFromGenerator'] as num).toStringAsFixed(3)} '
        '| ${(agg['avgEffectiveRetentionFromPhase9'] as num).toStringAsFixed(3)} '
        '| ${(agg['avgRoiMovedVertexCount'] as num).toStringAsFixed(0)} '
        '| ${((agg['avgGapVsFaceSlimPct'] as num) * 100).toStringAsFixed(1)}% '
        '| ${s['structuralPassAllFaces'] == true ? 'PASS' : 'FAIL'} '
        '| ${s['anySafetyGateFailAt100'] == true ? 'FAIL' : 'PASS'} '
        '| ${s['maxFieldFoldCountAt100']} '
        '| ${s['anyFieldFoldAt100'] == true ? 'sim' : 'não'} '
        '| ${s['regressionDetected'] == true ? 'SIM' : 'não'} |',
      );
    }

    buf
      ..writeln()
      ..writeln('![chart](stage6-$toolKey-chart.svg)');

    return buf.toString();
  }

  static String _svgChart(String toolKey, List<Map<String, dynamic>> steps) {
    const w = 640.0;
    const h = 360.0;
    const padL = 56.0;
    const padR = 24.0;
    const padT = 24.0;
    const padB = 48.0;
    final plotW = w - padL - padR;
    final plotH = h - padT - padB;

    final xs = steps.map((s) => s['maxDisplacementFse'] as double).toList();
    final synYs = steps
        .map(
          (s) =>
              ((s['aggregateSynthetic'] as Map)['avgEffectiveRoiMaxPx'] as num)
                  .toDouble(),
        )
        .toList();
    final realYs = steps
        .map(
          (s) => ((s['aggregateReal'] as Map)['avgEffectiveRoiMaxPx'] as num)
              .toDouble(),
        )
        .toList();
    final allYs = [...synYs, ...realYs];
    final minX = xs.reduce(math.min);
    final maxX = xs.reduce(math.max);
    final minY = allYs.reduce(math.min) * 0.95;
    final maxY = allYs.reduce(math.max) * 1.05;

    double xPos(double x) =>
        padL + (x - minX) / (maxX - minX + 1e-9) * plotW;
    double yPos(double y) =>
        padT + plotH - (y - minY) / (maxY - minY + 1e-9) * plotH;

    String poly(List<double> ys, String stroke) {
      final pts = <String>[];
      for (var i = 0; i < xs.length; i++) {
        pts.add('${xPos(xs[i]).toStringAsFixed(1)},${yPos(ys[i]).toStringAsFixed(1)}');
      }
      return '<polyline fill="none" stroke="$stroke" stroke-width="2" points="${pts.join(' ')}" />';
    }

    final baseline = baselineMaxDisplacementFse[toolKey]!;
    final refLine = faceSlimReferenceCap;

    return '''
<svg xmlns="http://www.w3.org/2000/svg" width="$w" height="$h" viewBox="0 0 $w $h">
  <rect width="$w" height="$h" fill="#fafafa"/>
  <text x="${w / 2}" y="16" text-anchor="middle" font-size="14" font-family="sans-serif">$toolKey — effective ROI max vs maxDisplacementFse</text>
  <line x1="$padL" y1="${padT + plotH}" x2="${padL + plotW}" y2="${padT + plotH}" stroke="#333"/>
  <line x1="$padL" y1="$padT" x2="$padL" y2="${padT + plotH}" stroke="#333"/>
  <line x1="${xPos(refLine)}" y1="$padT" x2="${xPos(refLine)}" y2="${padT + plotH}" stroke="#999" stroke-dasharray="4"/>
  <text x="${xPos(refLine)}" y="${h - 8}" text-anchor="middle" font-size="10" fill="#666">0.08 ref</text>
  <line x1="${xPos(baseline)}" y1="$padT" x2="${xPos(baseline)}" y2="${padT + plotH}" stroke="#ccc" stroke-dasharray="2"/>
  ${poly(synYs, '#2563eb')}
  ${poly(realYs, '#dc2626')}
  <circle cx="${padL + plotW - 80}" cy="${padT + 12}" r="4" fill="#2563eb"/>
  <text x="${padL + plotW - 70}" y="${padT + 16}" font-size="11" font-family="sans-serif">sintético</text>
  <circle cx="${padL + plotW - 80}" cy="${padT + 28}" r="4" fill="#dc2626"/>
  <text x="${padL + plotW - 70}" y="${padT + 32}" font-size="11" font-family="sans-serif">real</text>
  <text x="${w / 2}" y="${h - 28}" text-anchor="middle" font-size="11" font-family="sans-serif">maxDisplacementFse</text>
  <text x="16" y="${h / 2}" text-anchor="middle" font-size="11" font-family="sans-serif" transform="rotate(-90 16 ${h / 2})">eff ROI max (px)</text>
</svg>
''';
  }
}
