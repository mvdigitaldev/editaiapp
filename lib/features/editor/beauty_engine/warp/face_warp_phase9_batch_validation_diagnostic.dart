import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Offset, Size;

import '../body_reshape/maps/influence_map.dart';
import '../debug/agent_debug_log.dart';
import '../mesh/tri_mesh_spatial_index.dart';
import '../models/face_mesh_result.dart';
import '../models/tri_mesh.dart';
import '../segment/person_mask.dart';
import 'anatomy/anatomical_intent.dart';
import 'anatomy/face_matte_roi.dart';
import 'anatomy/face_mesh_deformation_engine.dart';
import 'experimental/global_jacobian_constraint.dart';
import 'experimental/triangle_jacobian_math.dart';
import 'face_warp_render_contract.dart';
import 'face_warp_renderer.dart' show GeometricSupport;

class Phase9BatchPhotoInput {
  const Phase9BatchPhotoInput({
    required this.id,
    required this.label,
    required this.face,
    required this.mesh,
    required this.width,
    required this.height,
    this.personMask,
  });

  final String id;
  final String label;
  final FaceMeshResult face;
  final TriMesh mesh;
  final int width;
  final int height;
  final PersonMask? personMask;
}

class FaceWarpPhase9BatchValidationResult {
  const FaceWarpPhase9BatchValidationResult({
    required this.summary,
    required this.summaryJsonPath,
  });

  final Map<String, dynamic> summary;
  final String summaryJsonPath;
}

/// Fase 12 — validação Phase 9 em lote (20–30 fotos reais).
abstract final class FaceWarpPhase9BatchValidationDiagnostic {
  FaceWarpPhase9BatchValidationDiagnostic._();

  static const _defaultOutputDir =
      '/Users/leonardo/Documents/Projetos/editaiapp/.cursor';

  static const _intensities = [0.3, 0.5, 0.7, 0.9, 1.0];
  static const _epsilon = 0.10;

  static Future<FaceWarpPhase9BatchValidationResult?> runBatch({
    required List<Phase9BatchPhotoInput> photos,
    String runId = 'phase9-batch-validation',
    String? outputDirectory,
  }) async {
    if (!kDebugMode) {
      return null;
    }

    try {
      final outDir = outputDirectory ?? _defaultOutputDir;
      Directory(outDir).createSync(recursive: true);

      const engine = FaceMeshDeformationEngine();
      final perPhoto = <Map<String, dynamic>>[];
      final failures = <Map<String, dynamic>>[];
      final allPhase9Rows = <Map<String, dynamic>>[];
      final allBaselineRows = <Map<String, dynamic>>[];

      for (final photo in photos) {
        debugPrint('P12 batch ${photo.id} ${photo.label}');

        try {
          final rows = _analyzePhoto(
            engine: engine,
            photo: photo,
          );
          perPhoto.add({
            'id': photo.id,
            'label': photo.label,
            'width': photo.width,
            'height': photo.height,
            'vertexCount': photo.mesh.vertices.length ~/ 2,
            'triangleCount': photo.mesh.triangleCount,
            'rows': rows,
            'safetySummary': _photoSafetySummary(rows),
          });

          for (final r in rows) {
            if (r['mode'] == 'PHASE9') {
              allPhase9Rows.add({...r, 'photoId': photo.id});
            } else if (r['mode'] == 'BASELINE') {
              allBaselineRows.add({...r, 'photoId': photo.id});
            }
          }

          AgentDebugLog.write(
            location: 'face_warp_phase9_batch_validation_diagnostic.dart:photo',
            message: 'phase12_batch_photo',
            hypothesisId: 'P12BV',
            runId: runId,
            phase: '12',
            data: {'id': photo.id, 'rows': rows.length},
          );
        } catch (e, st) {
          failures.add({
            'id': photo.id,
            'label': photo.label,
            'error': '$e',
            'stack': '$st',
          });
          debugPrint('P12_FAIL ${photo.id} $e');
        }
      }

      final aggregate = _aggregate(
        phase9Rows: allPhase9Rows,
        baselineRows: allBaselineRows,
        photoCount: photos.length,
        successCount: perPhoto.length,
      );

      final summary = {
        'phase': 12,
        'solver': 'GlobalJacobianConstraint',
        'epsilon': _epsilon,
        'intensities': _intensities,
        'photoCount': photos.length,
        'successCount': perPhoto.length,
        'failureCount': failures.length,
        'failures': failures,
        'aggregate': aggregate,
        'perPhoto': perPhoto,
        'recommendation': _recommendation(aggregate),
      };

      final summaryJsonPath =
          '$outDir/phase12_phase9_batch_validation_summary.json';
      File(summaryJsonPath).writeAsStringSync(jsonEncode(summary));

      AgentDebugLog.write(
        location: 'face_warp_phase9_batch_validation_diagnostic.dart:run',
        message: 'phase12_batch_summary',
        hypothesisId: 'P12BV',
        runId: runId,
        phase: '12',
        data: aggregate,
      );

      return FaceWarpPhase9BatchValidationResult(
        summary: summary,
        summaryJsonPath: summaryJsonPath,
      );
    } catch (e, st) {
      debugPrint('P12_BATCH_FAIL $e\n$st');
      return null;
    }
  }

  static List<Map<String, dynamic>> _analyzePhoto({
    required FaceMeshDeformationEngine engine,
    required Phase9BatchPhotoInput photo,
  }) {
    final imageSize = Size(photo.width.toDouble(), photo.height.toDouble());
    final influence = FaceMatteRoi.buildInfluenceMap(
      face: photo.face,
      imageSize: imageSize,
      personMask: photo.personMask,
      lateralRadiusExpand: 0.07,
    );
    final sourceIndex = TriMeshSpatialIndex(
      photo.mesh,
      imageWidth: photo.width.toDouble(),
      imageHeight: photo.height.toDouble(),
    );
    final roi = _roiFromMesh(photo.mesh, photo.width, photo.height);
    final vertexCount = photo.mesh.vertices.length ~/ 2;

    final rows = <Map<String, dynamic>>[];

    for (final intensity in _intensities) {
      final built = _buildPipeline(
        engine: engine,
        face: photo.face,
        mesh: photo.mesh,
        imageSize: imageSize,
        influence: influence,
        personMask: photo.personMask,
        width: photo.width,
        height: photo.height,
        intensity: intensity,
      );

      final original = built.effectiveDeltas;

      rows.add(_analyzeRow(
        mode: 'BASELINE',
        intensity: intensity,
        mesh: photo.mesh,
        sourceIndex: sourceIndex,
        roi: roi,
        vertexCount: vertexCount,
        original: original,
        applied: original,
        meta: null,
      ));

      final phase9 = GlobalJacobianConstraint.apply(
        mesh: photo.mesh,
        effectiveDeltas: original,
        epsilon: _epsilon,
        enabled: true,
      );

      rows.add(_analyzeRow(
        mode: 'PHASE9',
        intensity: intensity,
        mesh: photo.mesh,
        sourceIndex: sourceIndex,
        roi: roi,
        vertexCount: vertexCount,
        original: original,
        applied: phase9.constrainedDeltas,
        meta: {
          'constrainedVertexCount': phase9.constrainedVertexCount,
          'constrainedTriangleCount': phase9.constrainedTriangleCount,
          'constrainedVertexFraction': vertexCount > 0
              ? phase9.constrainedVertexCount / vertexCount
              : 0.0,
          'iterations': phase9.iterations,
          'converged': phase9.converged,
          'finalViolationCount': phase9.finalViolationCount,
        },
      ));
    }

    return rows;
  }

  static Map<String, dynamic> _photoSafetySummary(
    List<Map<String, dynamic>> rows,
  ) {
    final p9 = rows.where((r) => r['mode'] == 'PHASE9').toList();
    var allSafe = true;
    var worstMinJ = double.infinity;
    var totalTriFolds = 0;
    var totalFieldFolds = 0;

    for (final r in p9) {
      final triFolds = r['triangleFoldCount'] as int;
      final fieldFolds = r['fieldFoldCount'] as int;
      final minJ = r['minTriangleJ'] as double;
      totalTriFolds += triFolds;
      totalFieldFolds += fieldFolds;
      if (triFolds > 0 || fieldFolds > 0) {
        allSafe = false;
      }
      if (minJ < worstMinJ) {
        worstMinJ = minJ;
      }
    }

    return {
      'allIntensitiesSafe': allSafe,
      'worstMinTriangleJ': worstMinJ.isFinite ? worstMinJ : null,
      'totalTriangleFolds': totalTriFolds,
      'totalFieldFolds': totalFieldFolds,
    };
  }

  static Map<String, dynamic> _aggregate({
    required List<Map<String, dynamic>> phase9Rows,
    required List<Map<String, dynamic>> baselineRows,
    required int photoCount,
    required int successCount,
  }) {
    final byIntensity = <double, Map<String, dynamic>>{};

    for (final intensity in _intensities) {
      final p9At = phase9Rows
          .where((r) => (r['faceSlim'] as double) == intensity)
          .toList();
      final baseAt = baselineRows
          .where((r) => (r['faceSlim'] as double) == intensity)
          .toList();

      byIntensity[intensity] = {
        'faceSlim': intensity,
        'sampleCount': p9At.length,
        'safety': _aggSafety(p9At),
        'retention': _aggField(p9At, 'meanRetention'),
        'maxVertexJump': _aggField(p9At, 'maxVertexJump'),
        'jumpGt2': _aggFieldInt(p9At, 'jumpGt2'),
        'jumpGt5': _aggFieldInt(p9At, 'jumpGt5'),
        'constrainedVertices': _aggFieldInt(p9At, 'constrainedVertexCount'),
        'constrainedVertexFraction':
            _aggField(p9At, 'constrainedVertexFraction'),
        'baselineTriangleFolds': _aggFieldInt(baseAt, 'triangleFoldCount'),
        'baselineFieldFolds': _aggFieldInt(baseAt, 'fieldFoldCount'),
        'worstCases': _worstCases(p9At, intensity),
      };
    }

    final at90 = phase9Rows
        .where((r) => (r['faceSlim'] as double) == 0.9)
        .toList();

    return {
      'photoCount': photoCount,
      'successCount': successCount,
      'epsilon': _epsilon,
      'byIntensity': byIntensity.values.toList(),
      'at90': {
        'sampleCount': at90.length,
        'safetyPassRate': _safetyPassRate(at90),
        'retention': _aggField(at90, 'meanRetention'),
        'maxVertexJump': _aggField(at90, 'maxVertexJump'),
        'jumpGt2': _aggFieldInt(at90, 'jumpGt2'),
        'constrainedVertices': _aggFieldInt(at90, 'constrainedVertexCount'),
        'constrainedVertexFraction':
            _aggField(at90, 'constrainedVertexFraction'),
      },
      'overallSafetyPassRate': _safetyPassRate(phase9Rows),
    };
  }

  static double _safetyPassRate(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return 0.0;
    }
    var pass = 0;
    for (final r in rows) {
      if ((r['triangleFoldCount'] as int) == 0 &&
          (r['fieldFoldCount'] as int) == 0 &&
          (r['minTriangleJ'] as double) >=
              _epsilon - TriangleJacobianMath.jacobianTolerance) {
        pass++;
      }
    }
    return pass / rows.length;
  }

  static Map<String, dynamic> _aggSafety(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return {'passRate': 0.0};
    }
    var pass = 0;
    final minJs = <double>[];
    for (final r in rows) {
      minJs.add(r['minTriangleJ'] as double);
      if ((r['triangleFoldCount'] as int) == 0 &&
          (r['fieldFoldCount'] as int) == 0) {
        pass++;
      }
    }
    minJs.sort();
    return {
      'passRate': pass / rows.length,
      'minTriangleJ': _stats(minJs),
    };
  }

  static Map<String, dynamic> _aggField(
    List<Map<String, dynamic>> rows,
    String key,
  ) {
    final vals = rows
        .map((r) => r[key] as num?)
        .whereType<num>()
        .map((v) => v.toDouble())
        .toList();
    return _stats(vals);
  }

  static Map<String, dynamic> _aggFieldInt(
    List<Map<String, dynamic>> rows,
    String key,
  ) {
    final vals = rows.map((r) => (r[key] as num).toDouble()).toList();
    return _stats(vals);
  }

  static Map<String, dynamic> _stats(List<double> vals) {
    if (vals.isEmpty) {
      return {'mean': null, 'p50': null, 'p95': null, 'min': null, 'max': null};
    }
    vals.sort();
    return {
      'mean': vals.reduce((a, b) => a + b) / vals.length,
      'p50': _percentile(vals, 0.5),
      'p95': _percentile(vals, 0.95),
      'min': vals.first,
      'max': vals.last,
    };
  }

  static List<Map<String, dynamic>> _worstCases(
    List<Map<String, dynamic>> rows,
    double intensity,
  ) {
    final sorted = List<Map<String, dynamic>>.from(rows)
      ..sort((a, b) {
        final ja = a['minTriangleJ'] as double;
        final jb = b['minTriangleJ'] as double;
        return ja.compareTo(jb);
      });

    return sorted.take(3).map((r) {
      return {
        'photoId': r['photoId'],
        'faceSlim': intensity,
        'minTriangleJ': r['minTriangleJ'],
        'triangleFoldCount': r['triangleFoldCount'],
        'fieldFoldCount': r['fieldFoldCount'],
        'meanRetention': r['meanRetention'],
        'maxVertexJump': r['maxVertexJump'],
        'jumpGt2': r['jumpGt2'],
        'constrainedVertexCount': r['constrainedVertexCount'],
      };
    }).toList();
  }

  static String _recommendation(Map<String, dynamic> aggregate) {
    final at90 = aggregate['at90'] as Map<String, dynamic>;
    final passRate = at90['safetyPassRate'] as double;
    if (passRate >= 0.99) {
      return 'PHASE9_PRODUCTION_READY';
    }
    if (passRate >= 0.95) {
      return 'PHASE9_MOSTLY_SAFE_REVIEW_WORST_CASES';
    }
    return 'PHASE9_NOT_READY_REVIEW_FAILURES';
  }

  static Map<String, dynamic> _analyzeRow({
    required String mode,
    required double intensity,
    required TriMesh mesh,
    required TriMeshSpatialIndex sourceIndex,
    required ({int x0, int y0, int x1, int y1}) roi,
    required int vertexCount,
    required List<Offset> original,
    required List<Offset> applied,
    required Map<String, dynamic>? meta,
  }) {
    final meshJ = TriangleJacobianMath.allMeshJacobians(mesh, applied);
    final field = _scanFieldJacobian(
      sourceIndex: sourceIndex,
      deltas: applied,
      vertexCount: vertexCount,
      roi: roi,
    );
    final retention = _retentionStats(original, applied);
    final disp = _displacementStats(applied);
    final jumps = _vertexJumpStats(mesh, original, applied, vertexCount);

    return {
      'mode': mode,
      'faceSlim': intensity,
      'minTriangleJ': TriangleJacobianMath.minJacobian(meshJ),
      'triangleFoldCount': TriangleJacobianMath.countBelow(meshJ, 0),
      'minFieldJ': field.minJ,
      'fieldFoldCount': field.foldCount,
      'meanRetention': retention['mean'],
      'p50Retention': retention['p50'],
      'p95Retention': retention['p95'],
      'maxDisplacement': disp.max,
      'meanDisplacement': disp.mean,
      'maxVertexJump': jumps.maxJump,
      'p95VertexJump': jumps.p95Jump,
      'jumpGt2': jumps.gt2,
      'jumpGt5': jumps.gt5,
      'jumpGt10': jumps.gt10,
      if (meta != null) ...meta,
    };
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

  static ({
    double minJ,
    int foldCount,
  }) _scanFieldJacobian({
    required TriMeshSpatialIndex sourceIndex,
    required List<Offset> deltas,
    required int vertexCount,
    required ({int x0, int y0, int x1, int y1}) roi,
  }) {
    const gridStep = 4.0;
    final jValues = <double>[];
    var foldCount = 0;

    for (var y = roi.y0 + gridStep; y <= roi.y1 - gridStep; y += gridStep) {
      for (var x = roi.x0 + gridStep; x <= roi.x1 - gridStep; x += gridStep) {
        final j = TriangleJacobianMath.finiteDiffFieldJacobian(
          sourceIndex: sourceIndex,
          deltas: deltas,
          vertexCount: vertexCount,
          px: x + 0.5,
          py: y + 0.5,
        );
        if (j == null) {
          continue;
        }
        jValues.add(j);
        if (j <= 0) {
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
      return {'mean': 1.0, 'p50': 1.0, 'p95': 1.0};
    }
    return {
      'mean': ratios.reduce((a, b) => a + b) / ratios.length,
      'p50': _percentile(ratios, 0.5),
      'p95': _percentile(ratios, 0.95),
    };
  }

  static ({double max, double mean}) _displacementStats(List<Offset> deltas) {
    var max = 0.0;
    var sum = 0.0;
    for (final d in deltas) {
      max = math.max(max, d.distance);
      sum += d.distance;
    }
    return (max: max, mean: deltas.isEmpty ? 0.0 : sum / deltas.length);
  }

  static ({
    double maxJump,
    double p95Jump,
    int gt2,
    int gt5,
    int gt10,
  }) _vertexJumpStats(
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
    var gt2 = 0, gt5 = 0, gt10 = 0;
    for (final j in jumps) {
      if (j > 2) {
        gt2++;
      }
      if (j > 5) {
        gt5++;
      }
      if (j > 10) {
        gt10++;
      }
    }

    return (
      maxJump: jumps.isEmpty ? 0.0 : jumps.last,
      p95Jump: _percentile(jumps, 0.95),
      gt2: gt2,
      gt5: gt5,
      gt10: gt10,
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

  static double _percentile(List<double> sorted, double p) {
    if (sorted.isEmpty) {
      return 0.0;
    }
    final idx = ((sorted.length - 1) * p).round().clamp(0, sorted.length - 1);
    return sorted[idx];
  }
}
