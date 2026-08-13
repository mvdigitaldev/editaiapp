import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart' show Size;
import 'package:editaiapp/features/editor/beauty_engine/mesh/face_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/tri_mesh.dart';

import 'face_warp_mvp_calibration_diagnostic.dart';
import 'face_warp_mvp_structural_validation_diagnostic.dart';

/// Benchmark Stage 2 — before/after por ferramenta em múltiplos rostos.
abstract final class FaceWarpMvpCalibrationStage2Benchmark {
  FaceWarpMvpCalibrationStage2Benchmark._();

  static const _intensities = FaceWarpMvpCalibrationDiagnostic.defaultIntensities;

  static Future<Map<String, dynamic>> runToolCalibration({
    required String toolKey,
    required List<({
      String id,
      String label,
      FaceMeshResult face,
      Size imageSize,
      bool isSynthetic,
    })> faces,
    required String outputDirectory,
    String runId = 'stage2',
    bool validateFaceSlimStructural = false,
  }) async {
    Directory(outputDirectory).createSync(recursive: true);
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
        outputDirectory: '$outputDirectory/${f.id}',
        runId: '$runId-$toolKey-${f.id}',
        toolKeysFilter: [toolKey],
        writeHeatmaps: f.id == 'syn-oval',
      );

      final toolReport = (summary['tools'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((t) => t['toolKey'] == toolKey);
      final faceSlimRef = summary['faceSlimReferenceEffectiveRoiMaxPx'] as double;
      final at100 = (toolReport['intensityReports'] as List).last
          as Map<String, dynamic>;
      final effective = at100['effective'] as Map<String, dynamic>;

      perFace.add({
        'id': f.id,
        'label': f.label,
        'isSynthetic': f.isSynthetic,
        'faceSlimReferenceEffectiveRoiMaxPx': faceSlimRef,
        'effectiveRoiMaxPx': effective['roiMaxDisplacementPx'],
        'effectiveRoiMeanPx': effective['roiMeanDisplacementPx'],
        'roiMovedVertexCount': effective['roiMovedVertexCount'],
        'gapVsFaceSlimPct':
            _gapPct(faceSlimRef, effective['roiMaxDisplacementPx'] as double),
        'sliderCurve': _sliderCurve(toolReport),
        'bottleneck': toolReport['primaryBottleneck'],
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
      runId: '$runId-$toolKey-structural',
      skipFieldDiagnostics: true,
    );

    final faceSlimStructural = validateFaceSlimStructural
        ? FaceWarpMvpStructuralValidationDiagnostic.validateBatch(
            toolKey: 'face_slim',
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
            runId: '$runId-face_slim-structural',
          )
        : {'structuralPassAllFaces': true, 'skipped': true};

    final aggregate = _aggregate(perFace);

    final toolPass = structural['structuralPassAllFaces'] == true;
    final slimPass = faceSlimStructural['structuralPassAllFaces'] == true;

    final report = {
      'runId': runId,
      'toolKey': toolKey,
      'faceCount': faces.length,
      'intensities': _intensities,
      'aggregate': aggregate,
      'perFace': perFace,
      'structuralValidation': structural,
      'faceSlimStructuralValidation': faceSlimStructural,
      'phase14ProxyPass': toolPass && slimPass,
    };

    File('$outputDirectory/stage2-$toolKey-report.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(report),
    );
    File('$outputDirectory/stage2-$toolKey-report.md').writeAsStringSync(
      _markdown(toolKey, report),
    );

    return report;
  }

  static Map<String, dynamic> compareBeforeAfter({
    required Map<String, dynamic> before,
    required Map<String, dynamic> after,
  }) {
    final beforeFaces = (before['perFace'] as List).cast<Map<String, dynamic>>();
    final afterFaces = (after['perFace'] as List).cast<Map<String, dynamic>>();
    final comparisons = <Map<String, dynamic>>[];

    for (final b in beforeFaces) {
      final id = b['id'] as String;
      final a = afterFaces.firstWhere((f) => f['id'] == id);
      final beforeMax = b['effectiveRoiMaxPx'] as double;
      final afterMax = a['effectiveRoiMaxPx'] as double;
      final beforeMean = b['effectiveRoiMeanPx'] as double;
      final afterMean = a['effectiveRoiMeanPx'] as double;
      comparisons.add({
        'id': id,
        'label': b['label'],
        'isSynthetic': b['isSynthetic'],
        'beforeEffectiveRoiMaxPx': beforeMax,
        'afterEffectiveRoiMaxPx': afterMax,
        'maxGainPct': beforeMax > 1e-6 ? (afterMax - beforeMax) / beforeMax : 0,
        'beforeEffectiveRoiMeanPx': beforeMean,
        'afterEffectiveRoiMeanPx': afterMean,
        'meanGainPct':
            beforeMean > 1e-6 ? (afterMean - beforeMean) / beforeMean : 0,
        'beforeVertices': b['roiMovedVertexCount'],
        'afterVertices': a['roiMovedVertexCount'],
        'beforeGapVsFaceSlimPct': b['gapVsFaceSlimPct'],
        'afterGapVsFaceSlimPct': a['gapVsFaceSlimPct'],
      });
    }

    final maxGains =
        comparisons.map((c) => c['maxGainPct'] as double).toList();
    final meanGains =
        comparisons.map((c) => c['meanGainPct'] as double).toList();
    final avgMaxGain = maxGains.isEmpty
        ? 0.0
        : maxGains.reduce((a, b) => a + b) / maxGains.length;
    final avgMeanGain = meanGains.isEmpty
        ? 0.0
        : meanGains.reduce((a, b) => a + b) / meanGains.length;
    final minMaxGain = maxGains.isEmpty ? 0.0 : maxGains.reduce(math.min);

    return {
      'toolKey': after['toolKey'],
      'faceCount': comparisons.length,
      'avgMaxGainPct': avgMaxGain,
      'avgMeanGainPct': avgMeanGain,
      'minMaxGainPct': minMaxGain,
      'gainConsistent': minMaxGain >= avgMaxGain * 0.5,
      'beforeStructuralPass': before['phase14ProxyPass'],
      'afterStructuralPass': after['phase14ProxyPass'],
      'structuralStable':
          after['phase14ProxyPass'] == true && before['phase14ProxyPass'] == true,
      'perFace': comparisons,
    };
  }

  static Map<String, dynamic> _aggregate(List<Map<String, dynamic>> perFace) {
    if (perFace.isEmpty) {
      return {};
    }
    double sumMax = 0, sumMean = 0, sumGap = 0;
    var sumVertices = 0;
    for (final f in perFace) {
      sumMax += f['effectiveRoiMaxPx'] as double;
      sumMean += f['effectiveRoiMeanPx'] as double;
      sumGap += f['gapVsFaceSlimPct'] as double;
      sumVertices += f['roiMovedVertexCount'] as int;
    }
    final n = perFace.length;
    return {
      'avgEffectiveRoiMaxPx': sumMax / n,
      'avgEffectiveRoiMeanPx': sumMean / n,
      'avgGapVsFaceSlimPct': sumGap / n,
      'avgRoiMovedVertexCount': sumVertices / n,
    };
  }

  static double _gapPct(double ref, double value) {
    if (ref <= 1e-9) {
      return 0;
    }
    return (1.0 - value / ref).clamp(-1.0, 1.0);
  }

  static List<Map<String, dynamic>> _sliderCurve(Map<String, dynamic> tool) {
    return (tool['intensityReports'] as List).map((r) {
      final m = r as Map<String, dynamic>;
      final eff = m['effective'] as Map<String, dynamic>;
      return {
        'intensity': m['intensity'],
        'effectiveRoiMaxPx': eff['roiMaxDisplacementPx'],
        'effectiveRoiMeanPx': eff['roiMeanDisplacementPx'],
        'roiMovedVertexCount': eff['roiMovedVertexCount'],
      };
    }).toList();
  }

  static String _markdown(String toolKey, Map<String, dynamic> report) {
    final agg = report['aggregate'] as Map<String, dynamic>;
    final structural = report['structuralValidation'] as Map<String, dynamic>;
    final p14 = report['phase14ProxyPass'] == true ? 'PASS' : 'FAIL';
    final buf = StringBuffer()
      ..writeln('# Stage 2 — $toolKey')
      ..writeln()
      ..writeln('## Agregado (${report['faceCount']} rostos)')
      ..writeln(
        '- effective ROI max médio: '
        '${(agg['avgEffectiveRoiMaxPx'] as num).toStringAsFixed(2)} px',
      )
      ..writeln(
        '- effective ROI mean médio: '
        '${(agg['avgEffectiveRoiMeanPx'] as num).toStringAsFixed(2)} px',
      )
      ..writeln(
        '- vértices ROI médios: '
        '${(agg['avgRoiMovedVertexCount'] as num).toStringAsFixed(1)}',
      )
      ..writeln(
        '- gap vs face_slim médio: '
        '${((agg['avgGapVsFaceSlimPct'] as num) * 100).toStringAsFixed(1)}%',
      )
      ..writeln('- Phase 14 proxy: **$p14**')
      ..writeln(
        '- structural pass all faces: '
        '${structural['structuralPassAllFaces']}',
      )
      ..writeln()
      ..writeln('## Por rosto');
    for (final f in (report['perFace'] as List).cast<Map<String, dynamic>>()) {
      buf.writeln(
        '- **${f['label']}** (${f['id']}): '
        'max=${(f['effectiveRoiMaxPx'] as num).toStringAsFixed(2)} px, '
        'mean=${(f['effectiveRoiMeanPx'] as num).toStringAsFixed(2)} px, '
        'verts=${f['roiMovedVertexCount']}, '
        'gap=${((f['gapVsFaceSlimPct'] as num) * 100).toStringAsFixed(0)}%',
      );
    }
    return buf.toString();
  }
}
