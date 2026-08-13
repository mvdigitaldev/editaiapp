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
import 'experimental/field_fold_audit_math.dart';
import 'experimental/global_jacobian_safety_gate.dart';
import 'experimental/triangle_jacobian_math.dart';
import 'face_warp_phase9_batch_validation_diagnostic.dart';
import 'face_warp_render_contract.dart';
import 'face_warp_renderer.dart' show GeometricSupport;

class FaceWarpPhase9FinalValidationResult {
  const FaceWarpPhase9FinalValidationResult({
    required this.summary,
    required this.summaryJsonPath,
  });

  final Map<String, dynamic> summary;
  final String summaryJsonPath;
}

/// Fase 14 — validação final Phase 9 + Safety Gate estrutural.
abstract final class FaceWarpPhase9FinalValidationDiagnostic {
  FaceWarpPhase9FinalValidationDiagnostic._();

  static const _defaultOutputDir =
      '/Users/leonardo/Documents/Projetos/editaiapp/.cursor';

  static const _intensities = [0.3, 0.5, 0.7, 0.9, 1.0];
  static const _epsilon = 0.10;
  static const _fdH = 2.0;
  static const _gridStep = 4;

  static Future<FaceWarpPhase9FinalValidationResult?> runBatch({
    required List<Phase9BatchPhotoInput> photos,
    String runId = 'phase9-final-validation',
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
      final loadFailures = <Map<String, dynamic>>[];
      final allRows = <Map<String, dynamic>>[];
      final structuralFailures = <Map<String, dynamic>>[];

      for (final photo in photos) {
        debugPrint('P14 final ${photo.id} ${photo.label}');

        try {
          final rows = _analyzePhoto(engine: engine, photo: photo);
          var photoStructuralPass = true;

          for (final r in rows) {
            allRows.add({...r, 'photoId': photo.id});
            if (r['structuralPass'] != true) {
              photoStructuralPass = false;
              structuralFailures.add({
                'photoId': photo.id,
                'label': photo.label,
                'faceSlim': r['faceSlim'],
                'structuralChecks': r['structuralChecks'],
                'diagnostic': r['diagnostic'],
              });
            }
          }

          perPhoto.add({
            'id': photo.id,
            'label': photo.label,
            'width': photo.width,
            'height': photo.height,
            'structuralPassAllIntensities': photoStructuralPass,
            'rows': rows,
          });

          AgentDebugLog.write(
            location: 'face_warp_phase9_final_validation_diagnostic.dart:photo',
            message: 'phase14_final_photo',
            hypothesisId: 'P14FV',
            runId: runId,
            phase: '14',
            data: {'id': photo.id, 'structuralPass': photoStructuralPass},
          );
        } catch (e, st) {
          loadFailures.add({
            'id': photo.id,
            'label': photo.label,
            'error': '$e',
            'stack': '$st',
          });
        }
      }

      final totals = _computeTotals(allRows);
      final aggregate = _aggregate(allRows, photos.length, perPhoto.length);
      final recommendation = totals['structuralFailures'] == 0
          ? 'PHASE9_GO'
          : 'PHASE9_FAIL';

      final summary = {
        'phase': 14,
        'solver': 'GlobalJacobianConstraint',
        'safetyGate': 'GlobalJacobianSafetyGate',
        'epsilon': _epsilon,
        'fdDiagnosticH': _fdH,
        'intensities': _intensities,
        'photoCount': photos.length,
        'successCount': perPhoto.length,
        'loadFailureCount': loadFailures.length,
        'loadFailures': loadFailures,
        'totals': totals,
        'aggregate': aggregate,
        'structuralFailures': structuralFailures,
        'perPhoto': perPhoto,
        'safetyContract': _safetyContract(),
        'recommendation': recommendation,
      };

      final summaryJsonPath =
          '$outDir/phase14_phase9_final_validation_summary.json';
      File(summaryJsonPath).writeAsStringSync(jsonEncode(summary));

      AgentDebugLog.write(
        location: 'face_warp_phase9_final_validation_diagnostic.dart:run',
        message: 'phase14_final_summary',
        hypothesisId: 'P14FV',
        runId: runId,
        phase: '14',
        data: {'recommendation': recommendation, 'totals': totals},
      );

      return FaceWarpPhase9FinalValidationResult(
        summary: summary,
        summaryJsonPath: summaryJsonPath,
      );
    } catch (e, st) {
      debugPrint('P14_FINAL_FAIL $e\n$st');
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

      final gate = GlobalJacobianSafetyGate.validate(
        mesh: photo.mesh,
        originalDelta: built.effectiveDeltas,
        epsilon: _epsilon,
      );

      final applied = gate.outputDeltas;
      final diagnostic = _diagnosticMetrics(
        mesh: photo.mesh,
        sourceIndex: sourceIndex,
        roi: roi,
        vertexCount: vertexCount,
        deltas: applied,
      );

      final retention = _retentionStats(built.effectiveDeltas, applied);
      final jumps = _vertexJumpStats(
        photo.mesh,
        built.effectiveDeltas,
        applied,
        vertexCount,
      );

      rows.add({
        'faceSlim': intensity,
        'structuralPass': gate.passed,
        'fallbackUsed': gate.fallbackUsed,
        'structuralSafety': gate.structuralChecks,
        'diagnostic': diagnostic,
        'meanRetention': retention['mean'],
        'maxVertexJump': jumps.maxJump,
        'jumpGt2': jumps.gt2,
        'jumpGt5': jumps.gt5,
        'constrainedVertexCount': gate.phase9Result.constrainedVertexCount,
        'constrainedTriangleCount': gate.phase9Result.constrainedTriangleCount,
      });
    }

    return rows;
  }

  static Map<String, dynamic> _diagnosticMetrics({
    required TriMesh mesh,
    required TriMeshSpatialIndex sourceIndex,
    required ({int x0, int y0, int x1, int y1}) roi,
    required int vertexCount,
    required List<Offset> deltas,
  }) {
    final raw = _scanField(
      sourceIndex: sourceIndex,
      deltas: deltas,
      vertexCount: vertexCount,
      roi: roi,
      sameTriangleOnly: false,
      countBoundary: true,
    );
    final sameTri = _scanField(
      sourceIndex: sourceIndex,
      deltas: deltas,
      vertexCount: vertexCount,
      roi: roi,
      sameTriangleOnly: true,
      countBoundary: false,
    );
    final exactPl = _scanExactPl(
      mesh: mesh,
      sourceIndex: sourceIndex,
      deltas: deltas,
      vertexCount: vertexCount,
      roi: roi,
    );

    return {
      'rawFieldFoldCount': raw.foldCount,
      'minRawFieldJ': raw.minJ,
      'sameTriangleFieldFoldCount': sameTri.foldCount,
      'minSameTriangleFieldJ': sameTri.minJ,
      'boundaryCrossingCount': raw.boundaryCrossings,
      'exactPLFoldCount': exactPl.foldCount,
      'minExactPLJ': exactPl.minJ,
      'fdH': _fdH,
      'note':
          'Field metrics are diagnostic only; not used for structural PASS/FAIL',
    };
  }

  static Map<String, dynamic> _computeTotals(
    List<Map<String, dynamic>> rows,
  ) {
    var structuralPasses = 0;
    var structuralFailures = 0;
    var totalTriangleFolds = 0;
    var totalExactPlFolds = 0;
    var totalRawFdFolds = 0;
    var totalSameTriFdFolds = 0;
    var totalBoundaryCrossings = 0;
    final minTriangleJs = <double>[];

    for (final r in rows) {
      if (r['structuralPass'] == true) {
        structuralPasses++;
      } else {
        structuralFailures++;
      }

      final structural = r['structuralSafety'] as Map<String, dynamic>;
      totalTriangleFolds += structural['triangleFoldCount'] as int;
      minTriangleJs.add((structural['minTriangleJ'] as num).toDouble());

      final diag = r['diagnostic'] as Map<String, dynamic>;
      totalRawFdFolds += diag['rawFieldFoldCount'] as int;
      totalSameTriFdFolds += diag['sameTriangleFieldFoldCount'] as int;
      totalBoundaryCrossings += diag['boundaryCrossingCount'] as int;
      totalExactPlFolds += diag['exactPLFoldCount'] as int;
    }

    minTriangleJs.sort();

    return {
      'totalRuns': rows.length,
      'structuralPasses': structuralPasses,
      'structuralFailures': structuralFailures,
      'structuralPassRate':
          rows.isEmpty ? 0.0 : structuralPasses / rows.length,
      'totalTriangleFolds': totalTriangleFolds,
      'globalMinTriangleJ':
          minTriangleJs.isEmpty ? null : minTriangleJs.first,
      'totalExactPLFolds': totalExactPlFolds,
      'totalSameTriangleFieldFolds': totalSameTriFdFolds,
      'totalRawFieldFolds': totalRawFdFolds,
      'totalBoundaryCrossings': totalBoundaryCrossings,
    };
  }

  static Map<String, dynamic> _aggregate(
    List<Map<String, dynamic>> rows,
    int photoCount,
    int successCount,
  ) {
    final byIntensity = <Map<String, dynamic>>[];

    for (final intensity in _intensities) {
      final at = rows.where((r) => (r['faceSlim'] as double) == intensity).toList();
      var structPass = 0;
      for (final r in at) {
        if (r['structuralPass'] == true) {
          structPass++;
        }
      }

      byIntensity.add({
        'faceSlim': intensity,
        'sampleCount': at.length,
        'structuralSafety': {
          'passCount': structPass,
          'passRate': at.isEmpty ? 0.0 : structPass / at.length,
          'triangleFolds': _sumInt(at, 'structuralSafety', 'triangleFoldCount'),
          'minTriangleJ': _minNested(at, 'structuralSafety', 'minTriangleJ'),
        },
        'diagnosticMetrics': {
          'rawFieldFolds': _sumDiag(at, 'rawFieldFoldCount'),
          'sameTriangleFieldFolds': _sumDiag(at, 'sameTriangleFieldFoldCount'),
          'boundaryCrossings': _sumDiag(at, 'boundaryCrossingCount'),
          'exactPLFolds': _sumDiag(at, 'exactPLFoldCount'),
          'retentionMean': _meanField(at, 'meanRetention'),
          'jumpGt2Mean': _meanField(at, 'jumpGt2'),
        },
      });
    }

    return {
      'photoCount': photoCount,
      'successCount': successCount,
      'byIntensity': byIntensity,
    };
  }

  static int _sumInt(
    List<Map<String, dynamic>> rows,
    String outer,
    String inner,
  ) {
    var sum = 0;
    for (final r in rows) {
      sum += (r[outer] as Map)[inner] as int;
    }
    return sum;
  }

  static double? _minNested(
    List<Map<String, dynamic>> rows,
    String outer,
    String inner,
  ) {
    if (rows.isEmpty) {
      return null;
    }
    var min = double.infinity;
    for (final r in rows) {
      min = math.min(min, ((r[outer] as Map)[inner] as num).toDouble());
    }
    return min.isFinite ? min : null;
  }

  static int _sumDiag(List<Map<String, dynamic>> rows, String key) {
    var sum = 0;
    for (final r in rows) {
      sum += (r['diagnostic'] as Map)[key] as int;
    }
    return sum;
  }

  static double? _meanField(List<Map<String, dynamic>> rows, String key) {
    if (rows.isEmpty) {
      return null;
    }
    var sum = 0.0;
    for (final r in rows) {
      sum += (r[key] as num).toDouble();
    }
    return sum / rows.length;
  }

  static Map<String, dynamic> _safetyContract() {
    return {
      'structuralSafety': {
        'authority': 'exact piecewise-linear / triangle Jacobian',
        'enforcedBy': 'GlobalJacobianSafetyGate',
        'passCriteria': [
          'converged == true',
          'finalViolationCount == 0',
          'triangleFoldCount == 0',
          'minTriangleJ >= epsilon',
          'NaN displacement == 0',
          'Infinity displacement == 0',
        ],
        'onPass': 'return Phase 9 displacement',
        'onFail': 'return original displacement (existing safe fallback)',
      },
      'diagnosticMetrics': {
        'notUsedForFailure': ['rawFieldFoldCount'],
        'reportedSeparately': [
          'rawFieldFoldCount',
          'sameTriangleFieldFoldCount',
          'boundaryCrossingCount',
          'exactPLFoldCount',
          'jumpGt2',
          'jumpGt5',
          'maxVertexJump',
          'meanRetention',
        ],
        'note':
            'sameTriangleFieldFoldCount > 0 is diagnostic until proven to represent invalid deformation',
      },
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
    required bool sameTriangleOnly,
    required bool countBoundary,
  }) {
    final jValues = <double>[];
    var foldCount = 0;
    var boundaryCrossings = 0;

    for (var y = roi.y0 + _gridStep; y <= roi.y1 - _gridStep; y += _gridStep) {
      for (var x = roi.x0 + _gridStep; x <= roi.x1 - _gridStep; x += _gridStep) {
        final px = x + 0.5;
        final py = y + 0.5;

        if (countBoundary && !sameTriangleOnly) {
          final triP = sourceIndex.locateTriangleIndex(px, py);
          final triXm = sourceIndex.locateTriangleIndex(px - _fdH, py);
          final triXp = sourceIndex.locateTriangleIndex(px + _fdH, py);
          final triYm = sourceIndex.locateTriangleIndex(px, py - _fdH);
          final triYp = sourceIndex.locateTriangleIndex(px, py + _fdH);
          if (FieldFoldAuditMath.classifyStencil(
                triP: triP,
                triXm: triXm,
                triXp: triXp,
                triYm: triYm,
                triYp: triYp,
              ) ==
              FieldFoldStencilCategory.crossesTriangleBoundary) {
            boundaryCrossings++;
          }
        }

        final j = FieldFoldAuditMath.finiteDiffJacobian(
          sourceIndex: sourceIndex,
          deltas: deltas,
          vertexCount: vertexCount,
          px: px,
          py: py,
          h: _fdH,
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
        final i0 = mesh.indices[tri * 3];
        final i1 = mesh.indices[tri * 3 + 1];
        final i2 = mesh.indices[tri * 3 + 2];
        if (i0 >= vertexCount || i1 >= vertexCount || i2 >= vertexCount) {
          continue;
        }
        final j = TriangleJacobianMath.meshTriangleJacobian(
          mesh,
          deltas,
          i0,
          i1,
          i2,
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
      maxJump: jumps.isEmpty ? 0.0 : jumps.reduce(math.max),
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
}
