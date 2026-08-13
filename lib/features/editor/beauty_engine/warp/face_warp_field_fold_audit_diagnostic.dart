import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Offset, Size;
import 'package:image/image.dart' as img;

import '../body_reshape/maps/influence_map.dart';
import '../debug/agent_debug_log.dart';
import '../mesh/tri_mesh_spatial_index.dart';
import '../models/face_mesh_result.dart';
import '../models/tri_mesh.dart';
import '../segment/person_mask.dart';
import 'anatomy/anatomical_intent.dart';
import 'anatomy/face_matte_roi.dart';
import 'anatomy/face_mesh_deformation_engine.dart';
import 'experimental/field_fold_audit_math.dart';
import 'experimental/global_jacobian_constraint.dart';
import 'experimental/global_jacobian_safety_gate.dart';
import 'experimental/triangle_jacobian_math.dart';
import 'face_warp_render_contract.dart';
import 'face_warp_renderer.dart' show GeometricSupport;

class FaceWarpFieldFoldAuditResult {
  const FaceWarpFieldFoldAuditResult({
    required this.summary,
    required this.summaryJsonPath,
  });

  final Map<String, dynamic> summary;
  final String summaryJsonPath;
}

/// Fase 13 — auditoria de field folds FD vs malha (p26).
abstract final class FaceWarpFieldFoldAuditDiagnostic {
  FaceWarpFieldFoldAuditDiagnostic._();

  static const _defaultOutputDir =
      '/Users/leonardo/Documents/Projetos/editaiapp/.cursor';

  static const _intensities = [0.3, 0.5, 0.7, 0.9, 1.0];
  static const _epsilon = 0.10;
  static const _hValues = [0.5, 1.0, 2.0, 4.0, 8.0];
  static const _defaultH = 4.0;
  static const _gridStep = 4;

  static Future<FaceWarpFieldFoldAuditResult?> run({
    required FaceMeshResult face,
    required TriMesh mesh,
    required int width,
    required int height,
    PersonMask? personMask,
    Uint8List? backgroundRgba,
    String photoId = 'p26',
    String runId = 'field-fold-audit-p26',
    String? outputDirectory,
  }) async {
    if (!kDebugMode) {
      return null;
    }

    try {
      final outDir = outputDirectory ?? _defaultOutputDir;
      Directory(outDir).createSync(recursive: true);

      const engine = FaceMeshDeformationEngine();
      final imageSize = Size(width.toDouble(), height.toDouble());
      final influence = FaceMatteRoi.buildInfluenceMap(
        face: face,
        imageSize: imageSize,
        personMask: personMask,
        lateralRadiusExpand: 0.07,
      );
      final sourceIndex = TriMeshSpatialIndex(
        mesh,
        imageWidth: width.toDouble(),
        imageHeight: height.toDouble(),
      );
      final roi = _roiFromMesh(mesh, width, height);

      final intensityRows = <Map<String, dynamic>>[];
      final safetyGateRows = <Map<String, dynamic>>[];

      List<Offset>? deltas90;
      List<Offset>? original90;

      for (final intensity in _intensities) {
        debugPrint('P13 audit face_slim=$intensity');

        final built = _buildPipeline(
          engine: engine,
          face: face,
          mesh: mesh,
          imageSize: imageSize,
          influence: influence,
          personMask: personMask,
          width: width,
          height: height,
          intensity: intensity,
        );

        final phase9 = GlobalJacobianConstraint.apply(
          mesh: mesh,
          effectiveDeltas: built.effectiveDeltas,
          epsilon: _epsilon,
          enabled: true,
        );

        final gate = GlobalJacobianSafetyGate.validate(
          mesh: mesh,
          originalDelta: built.effectiveDeltas,
          epsilon: _epsilon,
        );

        final row = _metricsRow(
          intensity: intensity,
          mesh: mesh,
          sourceIndex: sourceIndex,
          roi: roi,
          vertexCount: built.vertexCount,
          original: built.effectiveDeltas,
          applied: phase9.constrainedDeltas,
          phase9: phase9,
          h: _defaultH,
        );
        intensityRows.add(row);

        safetyGateRows.add({
          'faceSlim': intensity,
          'passed': gate.passed,
          'fallbackUsed': gate.fallbackUsed,
          'checks': gate.structuralChecks,
        });

        if (intensity == 0.9) {
          deltas90 = phase9.constrainedDeltas;
          original90 = built.effectiveDeltas;
        }
      }

      if (deltas90 == null || original90 == null) {
        throw StateError('missing_0.9_deltas');
      }

      final hSweep = _hSweep(
        mesh: mesh,
        sourceIndex: sourceIndex,
        roi: roi,
        vertexCount: original90.length,
        deltas: deltas90,
      );

      final foldMap = _mapFieldFolds(
        mesh: mesh,
        sourceIndex: sourceIndex,
        roi: roi,
        vertexCount: original90.length,
        deltas: deltas90,
        h: _defaultH,
      );

      final interiorNegative = _interiorTriangleScan(
        mesh: mesh,
        sourceIndex: sourceIndex,
        roi: roi,
        vertexCount: original90.length,
        deltas: deltas90,
        h: _defaultH,
      );

      final conclusion = _buildConclusion(
        intensityRows: intensityRows,
        hSweep: hSweep,
        foldMap: foldMap,
        interiorNegative: interiorNegative,
        safetyGateRows: safetyGateRows,
      );

      final safetyContract = _safetyContract();

      if (backgroundRgba != null) {
        await _writePngs(
          outDir: outDir,
          backgroundRgba: backgroundRgba,
          width: width,
          height: height,
          mesh: mesh,
          sourceIndex: sourceIndex,
          roi: roi,
          vertexCount: original90.length,
          deltas: deltas90,
          foldMap: foldMap,
          h: _defaultH,
        );
      }

      final summary = {
        'phase': 13,
        'photoId': photoId,
        'epsilon': _epsilon,
        'defaultH': _defaultH,
        'intensitySweep': intensityRows,
        'hSweep': hSweep,
        'fieldFoldMap': foldMap,
        'interiorNegativeScan': interiorNegative,
        'safetyGate': safetyGateRows,
        'safetyContract': safetyContract,
        'conclusion': conclusion,
      };

      final summaryJsonPath = '$outDir/phase13_field_fold_audit_summary.json';
      File(summaryJsonPath).writeAsStringSync(jsonEncode(summary));

      AgentDebugLog.write(
        location: 'face_warp_field_fold_audit_diagnostic.dart:run',
        message: 'phase13_field_fold_audit_summary',
        hypothesisId: 'P13FF',
        runId: runId,
        phase: '13',
        data: conclusion,
      );

      return FaceWarpFieldFoldAuditResult(
        summary: summary,
        summaryJsonPath: summaryJsonPath,
      );
    } catch (e, st) {
      debugPrint('P13_FAIL $e\n$st');
      return null;
    }
  }

  static Map<String, dynamic> _metricsRow({
    required double intensity,
    required TriMesh mesh,
    required TriMeshSpatialIndex sourceIndex,
    required ({int x0, int y0, int x1, int y1}) roi,
    required int vertexCount,
    required List<Offset> original,
    required List<Offset> applied,
    required GlobalJacobianConstraintResult phase9,
    required double h,
  }) {
    final meshJ = phase9.triangleJacobiansAfter;
    final field = _scanField(
      sourceIndex: sourceIndex,
      deltas: applied,
      vertexCount: vertexCount,
      roi: roi,
      h: h,
      sameTriangleOnly: false,
    );
    final sameTri = _scanField(
      sourceIndex: sourceIndex,
      deltas: applied,
      vertexCount: vertexCount,
      roi: roi,
      h: h,
      sameTriangleOnly: true,
    );
    final exactPl = _scanExactPl(
      mesh: mesh,
      sourceIndex: sourceIndex,
      deltas: applied,
      vertexCount: vertexCount,
      roi: roi,
    );
    final retention = _retentionStats(original, applied);
    final jumps = _vertexJumpStats(mesh, original, applied, vertexCount);

    return {
      'faceSlim': intensity,
      'triangleFoldCount': TriangleJacobianMath.countBelow(meshJ, 0),
      'minTriangleJ': TriangleJacobianMath.minJacobian(meshJ),
      'fieldFoldCount': field.foldCount,
      'minFieldJ': field.minJ,
      'sameTriangleFieldFoldCount': sameTri.foldCount,
      'minSameTriangleFieldJ': sameTri.minJ,
      'boundaryCrossingCount': field.boundaryCrossings,
      'exactPlMinJ': exactPl.minJ,
      'exactPlFoldCount': exactPl.foldCount,
      'meanRetention': retention['mean'],
      'constrainedVertexCount': phase9.constrainedVertexCount,
      'maxVertexJump': jumps.maxJump,
      'jumpGt2': jumps.gt2,
      'jumpGt5': jumps.gt5,
      'iterations': phase9.iterations,
      'converged': phase9.converged,
      'finalViolationCount': phase9.finalViolationCount,
    };
  }

  static List<Map<String, dynamic>> _hSweep({
    required TriMesh mesh,
    required TriMeshSpatialIndex sourceIndex,
    required ({int x0, int y0, int x1, int y1}) roi,
    required int vertexCount,
    required List<Offset> deltas,
  }) {
    final rows = <Map<String, dynamic>>[];
    final meshJ = TriangleJacobianMath.allMeshJacobians(mesh, deltas);

    for (final h in _hValues) {
      final field = _scanField(
        sourceIndex: sourceIndex,
        deltas: deltas,
        vertexCount: vertexCount,
        roi: roi,
        h: h,
        sameTriangleOnly: false,
      );
      final sameTri = _scanField(
        sourceIndex: sourceIndex,
        deltas: deltas,
        vertexCount: vertexCount,
        roi: roi,
        h: h,
        sameTriangleOnly: true,
      );

      rows.add({
        'h': h,
        'fieldFolds': field.foldCount,
        'sameTriangleFolds': sameTri.foldCount,
        'boundaryCrossings': field.boundaryCrossings,
        'minFieldJ': field.minJ,
        'minSameTriangleFieldJ': sameTri.minJ,
        'triangleFolds': TriangleJacobianMath.countBelow(meshJ, 0),
        'minTriangleJ': TriangleJacobianMath.minJacobian(meshJ),
      });
    }
    return rows;
  }

  static Map<String, dynamic> _mapFieldFolds({
    required TriMesh mesh,
    required TriMeshSpatialIndex sourceIndex,
    required ({int x0, int y0, int x1, int y1}) roi,
    required int vertexCount,
    required List<Offset> deltas,
    required double h,
  }) {
    final folds = <Map<String, dynamic>>[];
    final boundaryCrossings = <Map<String, dynamic>>[];
    var categoryCounts = <String, int>{};

    for (var y = roi.y0 + _gridStep; y <= roi.y1 - _gridStep; y += _gridStep) {
      for (var x = roi.x0 + _gridStep; x <= roi.x1 - _gridStep; x += _gridStep) {
        final audit = FieldFoldAuditMath.auditPoint(
          mesh: mesh,
          sourceIndex: sourceIndex,
          deltas: deltas,
          vertexCount: vertexCount,
          px: x + 0.5,
          py: y + 0.5,
          h: h,
        );
        if (audit == null) {
          continue;
        }

        final label = FieldFoldAuditMath.categoryLabel(audit.category);
        categoryCounts[label] = (categoryCounts[label] ?? 0) + 1;

        if (audit.category ==
            FieldFoldStencilCategory.crossesTriangleBoundary) {
          boundaryCrossings.add(FieldFoldAuditMath.pointToJson(audit));
        }

        if (audit.fdJ < 0) {
          folds.add(FieldFoldAuditMath.pointToJson(audit));
        }
      }
    }

    return {
      'h': h,
      'gridStep': _gridStep,
      'fdFoldCount': folds.length,
      'boundaryCrossingCount': boundaryCrossings.length,
      'categoryCounts': categoryCounts,
      'folds': folds,
      'boundaryCrossings': boundaryCrossings,
    };
  }

  static Map<String, dynamic> _interiorTriangleScan({
    required TriMesh mesh,
    required TriMeshSpatialIndex sourceIndex,
    required ({int x0, int y0, int x1, int y1}) roi,
    required int vertexCount,
    required List<Offset> deltas,
    required double h,
  }) {
    var interiorSamples = 0;
    var interiorFdNegative = 0;
    var interiorSameTriNegative = 0;
    var interiorExactPlNegative = 0;

    for (var y = roi.y0 + _gridStep; y <= roi.y1 - _gridStep; y += _gridStep) {
      for (var x = roi.x0 + _gridStep; x <= roi.x1 - _gridStep; x += _gridStep) {
        final px = x + 0.5;
        final py = y + 0.5;
        final audit = FieldFoldAuditMath.auditPoint(
          mesh: mesh,
          sourceIndex: sourceIndex,
          deltas: deltas,
          vertexCount: vertexCount,
          px: px,
          py: py,
          h: h,
        );
        if (audit == null) {
          continue;
        }
        if (audit.category != FieldFoldStencilCategory.sameTriangle) {
          continue;
        }
        if (audit.minEdgeDistance < h * 1.5) {
          continue;
        }

        interiorSamples++;
        if (audit.fdJ < 0) {
          interiorFdNegative++;
        }
        if (audit.sameTriangleFdJ != null && audit.sameTriangleFdJ! < 0) {
          interiorSameTriNegative++;
        }
        if (audit.exactPlJ != null && audit.exactPlJ! < 0) {
          interiorExactPlNegative++;
        }
      }
    }

    return {
      'edgeMarginMultiplier': 1.5,
      'interiorSamples': interiorSamples,
      'interiorFdNegative': interiorFdNegative,
      'interiorSameTriFdNegative': interiorSameTriNegative,
      'interiorExactPlNegative': interiorExactPlNegative,
    };
  }

  static ({
    double minJ,
    int foldCount,
    int boundaryCrossings,
  }) _scanField({
    required TriMeshSpatialIndex sourceIndex,
    required List<Offset> deltas,
    required int vertexCount,
    required ({int x0, int y0, int x1, int y1}) roi,
    required double h,
    required bool sameTriangleOnly,
  }) {
    final jValues = <double>[];
    var foldCount = 0;
    var boundaryCrossings = 0;

    for (var y = roi.y0 + _gridStep; y <= roi.y1 - _gridStep; y += _gridStep) {
      for (var x = roi.x0 + _gridStep; x <= roi.x1 - _gridStep; x += _gridStep) {
        final px = x + 0.5;
        final py = y + 0.5;

        if (!sameTriangleOnly) {
          final triP = sourceIndex.locateTriangleIndex(px, py);
          final triXm = sourceIndex.locateTriangleIndex(px - h, py);
          final triXp = sourceIndex.locateTriangleIndex(px + h, py);
          final triYm = sourceIndex.locateTriangleIndex(px, py - h);
          final triYp = sourceIndex.locateTriangleIndex(px, py + h);
          final cat = FieldFoldAuditMath.classifyStencil(
            triP: triP,
            triXm: triXm,
            triXp: triXp,
            triYm: triYm,
            triYp: triYp,
          );
          if (cat == FieldFoldStencilCategory.crossesTriangleBoundary) {
            boundaryCrossings++;
          }
        }

        final j = FieldFoldAuditMath.finiteDiffJacobian(
          sourceIndex: sourceIndex,
          deltas: deltas,
          vertexCount: vertexCount,
          px: px,
          py: py,
          h: h,
          sameTriangleOnly: sameTriangleOnly,
        );
        if (j == null) {
          continue;
        }
        jValues.add(j);
        if (j < 0) {
          foldCount++;
        }
      }
    }

    jValues.sort();
    return (
      minJ: jValues.isEmpty ? 1.0 : jValues.first,
      foldCount: foldCount,
      boundaryCrossings: boundaryCrossings,
    );
  }

  static ({double minJ, int foldCount}) _scanExactPl({
    required TriMesh mesh,
    required TriMeshSpatialIndex sourceIndex,
    required List<Offset> deltas,
    required int vertexCount,
    required ({int x0, int y0, int x1, int y1}) roi,
  }) {
    final jValues = <double>[];
    var foldCount = 0;

    for (var y = roi.y0 + _gridStep; y <= roi.y1 - _gridStep; y += _gridStep) {
      for (var x = roi.x0 + _gridStep; x <= roi.x1 - _gridStep; x += _gridStep) {
        final tri = sourceIndex.locateTriangleIndex(x + 0.5, y + 0.5);
        if (tri == null) {
          continue;
        }
        final j = TriangleJacobianMath.exactFieldJacobianAtCentroid(
          mesh,
          deltas,
          tri,
        );
        jValues.add(j);
        if (j < 0) {
          foldCount++;
        }
      }
    }

    jValues.sort();
    return (
      minJ: jValues.isEmpty ? 1.0 : jValues.first,
      foldCount: foldCount,
    );
  }

  static Map<String, dynamic> _buildConclusion({
    required List<Map<String, dynamic>> intensityRows,
    required List<Map<String, dynamic>> hSweep,
    required Map<String, dynamic> foldMap,
    required Map<String, dynamic> interiorNegative,
    required List<Map<String, dynamic>> safetyGateRows,
  }) {
    final at90 = intensityRows.firstWhere(
      (r) => (r['faceSlim'] as double) == 0.9,
    );
    final h4 = hSweep.firstWhere((r) => (r['h'] as double) == 4.0);
    final folds = (foldMap['folds'] as List).cast<Map<String, dynamic>>();

    var boundaryFolds = 0;
    var sameTriFolds = 0;
    for (final f in folds) {
      if (f['category'] == 'CROSSES_TRIANGLE_BOUNDARY') {
        boundaryFolds++;
      } else if (f['category'] == 'SAME_TRIANGLE') {
        sameTriFolds++;
      }
    }

    final allStructuralSafe = safetyGateRows.every((g) => g['passed'] == true);
    final fieldFoldsReal = (interiorNegative['interiorFdNegative'] as int) > 0 ||
        (interiorNegative['interiorSameTriFdNegative'] as int) > 0;

    return {
      'fieldFoldsAreReal': fieldFoldsReal,
      'fieldFoldsAtBoundaries': boundaryFolds,
      'fieldFoldsSameTriangle': sameTriFolds,
      'sameTriangleFdFoldsAtH4': h4['sameTriangleFolds'],
      'fdDivergesNearEdges': boundaryFolds > 0 || sameTriFolds == 0,
      'anyTriangleJBelowZero': (at90['triangleFoldCount'] as int) > 0,
      'anyInteriorPointJBelowZero':
          (interiorNegative['interiorExactPlNegative'] as int) > 0,
      'phase9StructurallySafe': allStructuralSafe,
      'integrationRecommendation': allStructuralSafe && !fieldFoldsReal
          ? 'GO'
          : allStructuralSafe
              ? 'GO_WITH_DIAGNOSTIC_FIELD_CAVEAT'
              : 'NO-GO',
      'answers': {
        '1_fieldFoldsReal': fieldFoldsReal
            ? 'POSSIVELMENTE_SIM (interior negativo detectado)'
            : 'NAO — artefatos FD em fronteiras',
        '2_atBoundaries': boundaryFolds,
        '3_sameTriangleRemaining': h4['sameTriangleFolds'],
        '4_fdExactPlDivergeNearEdges': boundaryFolds > 0,
        '5_triangleJBelowZero': at90['triangleFoldCount'],
        '6_interiorJBelowZero': interiorNegative['interiorExactPlNegative'],
        '7_phase9StructurallySafe': allStructuralSafe,
      },
    };
  }

  static Map<String, dynamic> _safetyContract() {
    return {
      'structuralSafety': {
        'description': 'Critérios obrigatórios para produção',
        'checks': [
          'triangleFoldCount == 0',
          'minTriangleJ >= epsilon',
          'NaN count == 0',
          'Infinity count == 0',
          'converged == true',
          'finalViolationCount == 0',
        ],
        'enforcedBy': 'GlobalJacobianSafetyGate (experimental)',
      },
      'diagnosticQuality': {
        'description': 'Métricas de qualidade — não bloquear produção sem evidência',
        'metrics': [
          'fieldFoldCount (FD grid — pode ser artefato de stencil)',
          'sameTriangleFieldFoldCount (FD restrito — mais confiável)',
          'jumpGt2',
          'jumpGt5',
          'maxVertexVertex',
        ],
        'note':
            'Field folds FD que cruzam arestas NÃO indicam falha estrutural da malha',
      },
    };
  }

  static Future<void> _writePngs({
    required String outDir,
    required Uint8List backgroundRgba,
    required int width,
    required int height,
    required TriMesh mesh,
    required TriMeshSpatialIndex sourceIndex,
    required ({int x0, int y0, int x1, int y1}) roi,
    required int vertexCount,
    required List<Offset> deltas,
    required Map<String, dynamic> foldMap,
    required double h,
  }) async {
    img.Image baseFromRgba() {
      final image = img.Image(width: width, height: height);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final i = (y * width + x) * 4;
          image.setPixelRgba(
            x,
            y,
            backgroundRgba[i],
            backgroundRgba[i + 1],
            backgroundRgba[i + 2],
            backgroundRgba[i + 3],
          );
        }
      }
      return image;
    }

    void drawMesh(img.Image image) {
      for (var t = 0; t < mesh.triangleCount; t++) {
        final i0 = mesh.indices[t * 3];
        final i1 = mesh.indices[t * 3 + 1];
        final i2 = mesh.indices[t * 3 + 2];
        _drawLine(
          image,
          mesh.vertices[i0 * 2].round(),
          mesh.vertices[i0 * 2 + 1].round(),
          mesh.vertices[i1 * 2].round(),
          mesh.vertices[i1 * 2 + 1].round(),
          60,
          60,
          80,
          80,
        );
        _drawLine(
          image,
          mesh.vertices[i1 * 2].round(),
          mesh.vertices[i1 * 2 + 1].round(),
          mesh.vertices[i2 * 2].round(),
          mesh.vertices[i2 * 2 + 1].round(),
          60,
          60,
          80,
          80,
        );
        _drawLine(
          image,
          mesh.vertices[i2 * 2].round(),
          mesh.vertices[i2 * 2 + 1].round(),
          mesh.vertices[i0 * 2].round(),
          mesh.vertices[i0 * 2 + 1].round(),
          60,
          60,
          80,
          80,
        );
      }
    }

    // 1. original + mesh
    final meshImg = baseFromRgba();
    drawMesh(meshImg);
    File('$outDir/debug-face-p26-phase13-mesh.png')
        .writeAsBytesSync(img.encodePng(meshImg));

    // Helper: heatmap from scan function
    img.Image heatmap(
      double Function(double px, double py) jAt, {
      required String name,
    }) {
      final image = baseFromRgba();
      drawMesh(image);
      var minJ = double.infinity;
      var maxJ = -double.infinity;
      final samples = <(int x, int y, double j)>[];

      for (var y = roi.y0; y <= roi.y1; y += _gridStep) {
        for (var x = roi.x0; x <= roi.x1; x += _gridStep) {
          final j = jAt(x + 0.5, y + 0.5);
          if (j.isNaN || j.isInfinite) {
            continue;
          }
          minJ = math.min(minJ, j);
          maxJ = math.max(maxJ, j);
          samples.add((x, y, j));
        }
      }

      for (final (x, y, j) in samples) {
        final t = ((j - minJ) / (maxJ - minJ + 1e-9)).clamp(0.0, 1.0);
        final r = j < 0 ? 220 : (60 + (195 * t)).round();
        final g = j < 0 ? 40 : (180 * (1 - t)).round();
        final b = 60;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final px = x + dx;
            final py = y + dy;
            if (px >= 0 && py >= 0 && px < width && py < height) {
              image.setPixelRgb(px, py, r, g, b);
            }
          }
        }
      }
      return image;
    }

    // 2. FD fold points
    final fdImg = baseFromRgba();
    drawMesh(fdImg);
    for (final f in (foldMap['folds'] as List).cast<Map<String, dynamic>>()) {
      final x = (f['x'] as num).round();
      final y = (f['y'] as num).round();
      _markPoint(fdImg, x, y, 255, 40, 40);
    }
    File('$outDir/debug-face-p26-phase13-fd.png')
        .writeAsBytesSync(img.encodePng(fdImg));

    // 3. sameTriangleFD fold points
    final stImg = baseFromRgba();
    drawMesh(stImg);
    for (var y = roi.y0 + _gridStep; y <= roi.y1 - _gridStep; y += _gridStep) {
      for (var x = roi.x0 + _gridStep; x <= roi.x1 - _gridStep; x += _gridStep) {
        final j = FieldFoldAuditMath.finiteDiffJacobian(
          sourceIndex: sourceIndex,
          deltas: deltas,
          vertexCount: vertexCount,
          px: x + 0.5,
          py: y + 0.5,
          h: h,
          sameTriangleOnly: true,
        );
        if (j != null && j < 0) {
          _markPoint(stImg, x.round(), y.round(), 255, 140, 0);
        }
      }
    }
    File('$outDir/debug-face-p26-phase13-same-triangle-fd.png')
        .writeAsBytesSync(img.encodePng(stImg));

    // 4. boundary crossings
    final bcImg = baseFromRgba();
    drawMesh(bcImg);
    for (final f
        in (foldMap['boundaryCrossings'] as List).cast<Map<String, dynamic>>()) {
      final x = (f['x'] as num).round();
      final y = (f['y'] as num).round();
      _markPoint(bcImg, x, y, 255, 255, 0);
    }
    File('$outDir/debug-face-p26-phase13-boundaries.png')
        .writeAsBytesSync(img.encodePng(bcImg));

    // 5. triangle J heatmap
    final triJImg = heatmap((px, py) {
      final tri = sourceIndex.locateTriangleIndex(px, py);
      if (tri == null) {
        return double.nan;
      }
      final i0 = mesh.indices[tri * 3];
      final i1 = mesh.indices[tri * 3 + 1];
      final i2 = mesh.indices[tri * 3 + 2];
      return TriangleJacobianMath.meshTriangleJacobian(mesh, deltas, i0, i1, i2);
    }, name: 'tri');
    File('$outDir/debug-face-p26-phase13-triangle-j.png')
        .writeAsBytesSync(img.encodePng(triJImg));

    // 6. FD J heatmap
    final fdJImg = heatmap((px, py) {
      return FieldFoldAuditMath.finiteDiffJacobian(
            sourceIndex: sourceIndex,
            deltas: deltas,
            vertexCount: vertexCount,
            px: px,
            py: py,
            h: h,
            sameTriangleOnly: false,
          ) ??
          double.nan;
    }, name: 'fd');
    File('$outDir/debug-face-p26-phase13-field-j.png')
        .writeAsBytesSync(img.encodePng(fdJImg));

    // 7. exact PL heatmap
    final plImg = heatmap((px, py) {
      final tri = sourceIndex.locateTriangleIndex(px, py);
      if (tri == null) {
        return double.nan;
      }
      return TriangleJacobianMath.exactFieldJacobianAtCentroid(mesh, deltas, tri);
    }, name: 'pl');
    File('$outDir/debug-face-p26-phase13-exact-pl-j.png')
        .writeAsBytesSync(img.encodePng(plImg));

    // crops around worst fold
    final folds = (foldMap['folds'] as List).cast<Map<String, dynamic>>();
    if (folds.isNotEmpty) {
      folds.sort((a, b) => (a['fdJ'] as num).compareTo(b['fdJ'] as num));
      final worst = folds.first;
      final cx = (worst['x'] as num).round();
      final cy = (worst['y'] as num).round();
      const cropR = 80;
      final crop = img.copyCrop(
        fdImg,
        x: (cx - cropR).clamp(0, width - 1),
        y: (cy - cropR).clamp(0, height - 1),
        width: (cropR * 2).clamp(1, width),
        height: (cropR * 2).clamp(1, height),
      );
      File('$outDir/debug-face-p26-phase13-hotspot-crop.png')
          .writeAsBytesSync(img.encodePng(crop));
    }
  }

  static void _markPoint(img.Image image, int x, int y, int r, int g, int b) {
    for (var dy = -3; dy <= 3; dy++) {
      for (var dx = -3; dx <= 3; dx++) {
        final px = x + dx;
        final py = y + dy;
        if (px >= 0 && py >= 0 && px < image.width && py < image.height) {
          image.setPixelRgb(px, py, r, g, b);
        }
      }
    }
  }

  static ({
    dynamic vertexField,
    List<Offset> effectiveDeltas,
    Float32List supportWeights,
    int vertexCount,
  }) _buildPipeline({
    required FaceMeshDeformationEngine engine,
    required FaceMeshResult face,
    required TriMesh mesh,
    required Size imageSize,
    required InfluenceMap influence,
    required PersonMask? personMask,
    required int width,
    required int height,
    required double intensity,
  }) {
    final vertexField = engine.composeVertexField(
      parameters: {'face_slim': intensity},
      context: FaceAnatomyContext(
        face: face,
        imageSize: imageSize,
        mesh: mesh,
      ),
    );
    final vertexCount = FaceWarpFieldMetrics.safeVertexCount(
      field: vertexField,
      mesh: mesh,
    );
    final supportWeights = GeometricSupport.computeWeights(
      mesh: mesh,
      coreField: vertexField,
      influenceMap: influence,
      params: const DeformationSupportParams(),
      imageWidth: width,
      imageHeight: height,
      personMask: personMask,
    );
    final effectiveDeltas = List<Offset>.generate(
      vertexCount,
      (i) => FaceWarpFieldMetrics.effectiveDelta(
        vertexField.displacementAt(i),
        supportWeights[i].clamp(0.0, 1.0),
      ),
    );
    return (
      vertexField: vertexField,
      effectiveDeltas: effectiveDeltas,
      supportWeights: supportWeights,
      vertexCount: vertexCount,
    );
  }

  static Map<String, dynamic> _retentionStats(
    List<Offset> original,
    List<Offset> constrained,
  ) {
    final ratios = <double>[];
    for (var i = 0; i < original.length; i++) {
      final o = original[i].distance;
      if (o < 1e-6) {
        continue;
      }
      ratios.add(constrained[i].distance / o);
    }
    ratios.sort();
    if (ratios.isEmpty) {
      return {'mean': 1.0};
    }
    return {'mean': ratios.reduce((a, b) => a + b) / ratios.length};
  }

  static ({double maxJump, int gt2, int gt5}) _vertexJumpStats(
    TriMesh mesh,
    List<Offset> before,
    List<Offset> after,
    int vertexCount,
  ) {
    final seen = <String>{};
    final jumps = <double>[];

    for (var t = 0; t < mesh.triangleCount; t++) {
      final verts = [
        mesh.indices[t * 3],
        mesh.indices[t * 3 + 1],
        mesh.indices[t * 3 + 2],
      ];
      for (var e = 0; e < 3; e++) {
        final a = verts[e];
        final b = verts[(e + 1) % 3];
        if (a >= vertexCount || b >= vertexCount) {
          continue;
        }
        final lo = a < b ? a : b;
        final hi = a < b ? b : a;
        final key = '$lo-$hi';
        if (seen.contains(key)) {
          continue;
        }
        seen.add(key);

        final ddx = (after[a].dx - after[b].dx) - (before[a].dx - before[b].dx);
        final ddy = (after[a].dy - after[b].dy) - (before[a].dy - before[b].dy);
        jumps.add(math.sqrt(ddx * ddx + ddy * ddy));
      }
    }

    jumps.sort();
    var gt2 = 0, gt5 = 0;
    for (final j in jumps) {
      if (j > 2) {
        gt2++;
      }
      if (j > 5) {
        gt5++;
      }
    }

    return (
      maxJump: jumps.isEmpty ? 0.0 : jumps.last,
      gt2: gt2,
      gt5: gt5,
    );
  }

  static ({
    int x0,
    int y0,
    int x1,
    int y1,
  }) _roiFromMesh(TriMesh mesh, int width, int height) {
    var minX = width;
    var minY = height;
    var maxX = 0;
    var maxY = 0;
    for (var i = 0; i < mesh.vertices.length; i += 2) {
      minX = math.min(minX, mesh.vertices[i].floor());
      minY = math.min(minY, mesh.vertices[i + 1].floor());
      maxX = math.max(maxX, mesh.vertices[i].ceil());
      maxY = math.max(maxY, mesh.vertices[i + 1].ceil());
    }
    const margin = 3;
    return (
      x0: (minX - margin).clamp(0, width - 1),
      y0: (minY - margin).clamp(0, height - 1),
      x1: (maxX + margin).clamp(0, width - 1),
      y1: (maxY + margin).clamp(0, height - 1),
    );
  }

  static void _drawLine(
    img.Image image,
    int x0,
    int y0,
    int x1,
    int y1,
    int r,
    int g,
    int b,
    int a,
  ) {
    final steps = math.max((x1 - x0).abs(), (y1 - y0).abs());
    if (steps == 0) {
      return;
    }
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = (x0 + (x1 - x0) * t).round();
      final y = (y0 + (y1 - y0) * t).round();
      if (x >= 0 && y >= 0 && x < image.width && y < image.height) {
        image.setPixelRgba(x, y, r, g, b, a);
      }
    }
  }
}
