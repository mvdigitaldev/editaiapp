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
import 'experimental/global_jacobian_constraint.dart';
import 'experimental/global_jacobian_displacement_optimizer.dart';
import 'experimental/triangle_jacobian_math.dart';
import 'face_warp_render_contract.dart';
import 'face_warp_renderer.dart' show GeometricSupport;

class FaceWarpGlobalDisplacementOptimizerDiagnosticResult {
  const FaceWarpGlobalDisplacementOptimizerDiagnosticResult({
    required this.summary,
    required this.summaryJsonPath,
  });

  final Map<String, dynamic> summary;
  final String summaryJsonPath;
}

/// Fase 11 — otimização global de displacement (experimental).
abstract final class FaceWarpGlobalDisplacementOptimizerDiagnostic {
  FaceWarpGlobalDisplacementOptimizerDiagnostic._();

  static const _defaultOutputDir =
      '/Users/leonardo/Documents/Projetos/editaiapp/.cursor';

  static const _intensities = [0.3, 0.5, 0.7, 0.9, 1.0];
  static const _lambdas = [0.25, 0.5, 1.0];
  static const _epsilon = 0.10;
  static const _pngIntensities = [0.3, 0.5, 0.7, 0.9];

  static const _criticalVertices = [356, 127];
  static const _hotspot = (532.0, 439.0);

  static Future<FaceWarpGlobalDisplacementOptimizerDiagnosticResult?> run({
    required FaceMeshResult face,
    required TriMesh mesh,
    required int width,
    required int height,
    PersonMask? personMask,
    String runId = 'global-displacement-opt-real',
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

      final sweepRows = <Map<String, dynamic>>[];
      final lambdaSummary = <Map<String, dynamic>>[];
      final baselineChecks = <Map<String, dynamic>>[];
      final stabilityTests = <Map<String, dynamic>>[];
      final safetyTests = <Map<String, dynamic>>[];
      final regressionTests = <Map<String, dynamic>>[];
      final hotspotDebug = <Map<String, dynamic>>[];

      for (final intensity in _intensities) {
        debugPrint('P11 displacement-opt face_slim=$intensity');

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

        final original = built.effectiveDeltas;

        sweepRows.add(_analyze(
          mode: 'BASELINE',
          intensity: intensity,
          lambda: null,
          mesh: mesh,
          sourceIndex: sourceIndex,
          roi: roi,
          original: original,
          applied: original,
          phase9: original,
          meta: null,
        ));

        final phase9 = GlobalJacobianConstraint.apply(
          mesh: mesh,
          effectiveDeltas: original,
          epsilon: _epsilon,
          enabled: true,
        );

        sweepRows.add(_analyze(
          mode: 'PHASE9',
          intensity: intensity,
          lambda: null,
          mesh: mesh,
          sourceIndex: sourceIndex,
          roi: roi,
          original: original,
          applied: phase9.constrainedDeltas,
          phase9: phase9.constrainedDeltas,
          meta: {
            'iterations': phase9.iterations,
            'converged': phase9.converged,
            'constrainedVertexCount': phase9.constrainedVertexCount,
            'constrainedTriangleCount': phase9.constrainedTriangleCount,
          },
        ));

        final disabled = GlobalJacobianDisplacementOptimizer.apply(
          mesh: mesh,
          originalDelta: original,
          epsilon: _epsilon,
          enabled: false,
        );
        baselineChecks.add({
          'faceSlim': intensity,
          'identityOk': _deltasIdentical(
            phase9.constrainedDeltas,
            disabled.constrainedDeltas,
          ),
        });

        for (final lambda in _lambdas) {
          final p11 = GlobalJacobianDisplacementOptimizer.apply(
            mesh: mesh,
            originalDelta: original,
            epsilon: _epsilon,
            enabled: true,
            lambda: lambda,
          );

          var safetyOk = true;
          final meshJ = p11.triangleJacobiansAfter;
          if (TriangleJacobianMath.countBelow(meshJ, 0) > 0 ||
              TriangleJacobianMath.minJacobian(meshJ) <
                  _epsilon - TriangleJacobianMath.jacobianTolerance) {
            safetyOk = false;
          }

          safetyTests.add({
            'faceSlim': intensity,
            'lambda': lambda,
            'safetyOk': safetyOk,
            'minTriangleJ': TriangleJacobianMath.minJacobian(meshJ),
            'triangleFoldCount': TriangleJacobianMath.countBelow(meshJ, 0),
          });

          final row = _analyze(
            mode: 'PHASE11_L${_lambdaLabel(lambda)}',
            intensity: intensity,
            lambda: lambda,
            mesh: mesh,
            sourceIndex: sourceIndex,
            roi: roi,
            original: original,
            applied: p11.constrainedDeltas,
            phase9: phase9.constrainedDeltas,
            meta: {
              'iterations': p11.iterations,
              'converged': p11.converged,
              'finalObjective': p11.finalObjective,
              'alteredVertexCount': p11.alteredVertexCount,
              'iterationLog': p11.iterationLog,
            },
          );
          sweepRows.add(row);

          if (intensity == 0.9) {
            hotspotDebug.addAll(
              _hotspotRecords(
                intensity: intensity,
                lambda: lambda,
                mesh: mesh,
                original: original,
                phase9Deltas: phase9.constrainedDeltas,
                result: p11,
              ),
            );
          }

          AgentDebugLog.write(
            location:
                'face_warp_global_displacement_optimizer_diagnostic.dart:sweep',
            message: 'phase11_displacement_optimizer_diagnostic',
            hypothesisId: 'P11DO',
            runId: runId,
            phase: '11',
            data: row,
          );
        }
      }

      // Regressão faceSlim=0
      final builtZero = _buildPipeline(
        engine: engine,
        face: face,
        mesh: mesh,
        imageSize: imageSize,
        influence: influence,
        personMask: personMask,
        width: width,
        height: height,
        intensity: 0.0,
      );
      final p11Zero = GlobalJacobianDisplacementOptimizer.apply(
        mesh: mesh,
        originalDelta: builtZero.effectiveDeltas,
        epsilon: _epsilon,
        enabled: true,
      );
      regressionTests.add({
        'test': 'faceSlim_zero',
        'allZero': p11Zero.constrainedDeltas.every(
          (d) => d.dx.abs() < 1e-9 && d.dy.abs() < 1e-9,
        ),
      });

      // Regressão: sem violações → não altera
      final builtSafe = _buildPipeline(
        engine: engine,
        face: face,
        mesh: mesh,
        imageSize: imageSize,
        influence: influence,
        personMask: personMask,
        width: width,
        height: height,
        intensity: 0.1,
      );
      final p9Safe = GlobalJacobianConstraint.apply(
        mesh: mesh,
        effectiveDeltas: builtSafe.effectiveDeltas,
        epsilon: _epsilon,
        enabled: true,
      );
      final baselineJ = TriangleJacobianMath.allMeshJacobians(
        mesh,
        builtSafe.effectiveDeltas,
      );
      final baselineMinJ = TriangleJacobianMath.minJacobian(baselineJ);
      final p11Safe = GlobalJacobianDisplacementOptimizer.apply(
        mesh: mesh,
        originalDelta: builtSafe.effectiveDeltas,
        epsilon: _epsilon,
        enabled: true,
        lambda: 0.5,
      );
      regressionTests.add({
        'test': 'no_violations_noop',
        'baselineMinJ': baselineMinJ,
        'baselineAlreadySafe': baselineMinJ >= _epsilon,
        'identicalToPhase9': _deltasIdentical(
          p9Safe.constrainedDeltas,
          p11Safe.constrainedDeltas,
        ),
      });

      // Estabilidade @0.9 lambda=0.5
      final built90 = _buildPipeline(
        engine: engine,
        face: face,
        mesh: mesh,
        imageSize: imageSize,
        influence: influence,
        personMask: personMask,
        width: width,
        height: height,
        intensity: 0.9,
      );
      final forward = GlobalJacobianDisplacementOptimizer.apply(
        mesh: mesh,
        originalDelta: built90.effectiveDeltas,
        epsilon: _epsilon,
        enabled: true,
        lambda: 0.5,
      );
      final reverse = GlobalJacobianDisplacementOptimizer.apply(
        mesh: mesh,
        originalDelta: built90.effectiveDeltas,
        epsilon: _epsilon,
        enabled: true,
        lambda: 0.5,
        triangleOrder: List.generate(mesh.triangleCount, (i) => i).reversed
            .toList(),
      );
      final shuffled = List.generate(mesh.triangleCount, (i) => i);
      shuffled.shuffle(math.Random(42));
      final shuffledResult = GlobalJacobianDisplacementOptimizer.apply(
        mesh: mesh,
        originalDelta: built90.effectiveDeltas,
        epsilon: _epsilon,
        enabled: true,
        lambda: 0.5,
        triangleOrder: shuffled,
      );

      stabilityTests.add({
        'faceSlim': 0.9,
        'lambda': 0.5,
        'forwardReverseIdentical': _deltasIdentical(
          forward.constrainedDeltas,
          reverse.constrainedDeltas,
        ),
        'forwardShuffledIdentical': _deltasIdentical(
          forward.constrainedDeltas,
          shuffledResult.constrainedDeltas,
        ),
        'orderStable': _deltasIdentical(
          forward.constrainedDeltas,
          reverse.constrainedDeltas,
        ) &&
            _deltasIdentical(
              forward.constrainedDeltas,
              shuffledResult.constrainedDeltas,
            ),
      });

      for (final lambda in _lambdas) {
        lambdaSummary.add(_summarizeLambda(sweepRows, lambda));
      }

      final bestLambda = _pickBestLambda(lambdaSummary);

      for (final intensity in _pngIntensities) {
        await _writeComparisonPngs(
          outDir: outDir,
          engine: engine,
          face: face,
          mesh: mesh,
          imageSize: imageSize,
          influence: influence,
          personMask: personMask,
          width: width,
          height: height,
          sourceIndex: sourceIndex,
          intensity: intensity,
          bestLambda: bestLambda,
        );
      }

      final conclusion = _buildConclusion(sweepRows, lambdaSummary, bestLambda);

      final summary = {
        'epsilon': _epsilon,
        'formulation': {
          'variables': 'finalDx[v] with dy=0',
          'objective':
              'preserve(originalDx) + lambda * smooth(edges) projected onto J>=epsilon',
          'constraints': 'linear per triangle: J = 1 + sum(c_tv * dx_v) >= epsilon',
          'solver': 'projected Jacobi from Phase9 seed',
        },
        'baselinePreserved':
            baselineChecks.every((r) => r['identityOk'] == true),
        'baselineChecks': baselineChecks,
        'regressionTests': regressionTests,
        'stabilityTests': stabilityTests,
        'safetyTests': safetyTests,
        'allSafetyPassed': safetyTests.every((r) => r['safetyOk'] == true),
        'lambdaComparison': lambdaSummary,
        'bestLambda': bestLambda,
        'hotspotDebug': hotspotDebug,
        'conclusion': conclusion,
        'sweep': sweepRows,
      };

      final summaryJsonPath =
          '$outDir/phase11_global_displacement_optimization_summary.json';
      File(summaryJsonPath).writeAsStringSync(jsonEncode(summary));

      AgentDebugLog.write(
        location: 'face_warp_global_displacement_optimizer_diagnostic.dart:run',
        message: 'phase11_displacement_optimizer_summary',
        hypothesisId: 'P11DO',
        runId: runId,
        phase: '11',
        data: summary,
      );

      return FaceWarpGlobalDisplacementOptimizerDiagnosticResult(
        summary: summary,
        summaryJsonPath: summaryJsonPath,
      );
    } catch (e, st) {
      debugPrint('P11_FAIL $e\n$st');
      return null;
    }
  }

  static Map<String, dynamic> _analyze({
    required String mode,
    required double intensity,
    required double? lambda,
    required TriMesh mesh,
    required TriMeshSpatialIndex sourceIndex,
    required ({int x0, int y0, int x1, int y1}) roi,
    required List<Offset> original,
    required List<Offset> applied,
    required List<Offset> phase9,
    required Map<String, dynamic>? meta,
  }) {
    final meshJ = TriangleJacobianMath.allMeshJacobians(mesh, applied);
    final field = _scanFieldJacobian(
      sourceIndex: sourceIndex,
      deltas: applied,
      vertexCount: original.length,
      roi: roi,
    );
    final retention = _retentionStats(original, applied);
    final disp = _displacementStats(applied);
    final jumps = _vertexJumpStats(mesh, original, applied, original.length);
    final locality = _localityStats(
      mesh: mesh,
      original: original,
      phase9: phase9,
      applied: applied,
    );

    return {
      'mode': mode,
      'faceSlim': intensity,
      'lambda': lambda,
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
      ...locality,
      if (meta != null) ...meta,
    };
  }

  static Map<String, dynamic> _localityStats({
    required TriMesh mesh,
    required List<Offset> original,
    required List<Offset> phase9,
    required List<Offset> applied,
  }) {
    var altered = 0;
    var gt5 = 0;
    var gt10 = 0;
    final distances = <double>[];

    for (var v = 0; v < original.length; v++) {
      final delta = (applied[v].dx - phase9[v].dx).abs();
      if (delta > 1e-6) {
        altered++;
        final ref = original[v].dx.abs();
        if (ref > 1e-6) {
          final ratio = delta / ref;
          if (ratio > 0.05) {
            gt5++;
          }
          if (ratio > 0.10) {
            gt10++;
          }
        }
        final vx = mesh.vertices[v * 2];
        final vy = mesh.vertices[v * 2 + 1];
        var minDist = double.infinity;
        for (final cv in _criticalVertices) {
          if (cv >= mesh.vertices.length ~/ 2) {
            continue;
          }
          final cx = mesh.vertices[cv * 2];
          final cy = mesh.vertices[cv * 2 + 1];
          final d = math.sqrt(
            (vx - cx) * (vx - cx) + (vy - cy) * (vy - cy),
          );
          minDist = math.min(minDist, d);
        }
        final hx = _hotspot.$1;
        final hy = _hotspot.$2;
        minDist = math.min(
          minDist,
          math.sqrt((vx - hx) * (vx - hx) + (vy - hy) * (vy - hy)),
        );
        distances.add(minDist);
      }
    }

    var alteredTris = 0;
    for (var t = 0; t < mesh.triangleCount; t++) {
      final verts = [
        mesh.indices[t * 3],
        mesh.indices[t * 3 + 1],
        mesh.indices[t * 3 + 2],
      ];
      var triAltered = false;
      for (final v in verts) {
        if (v >= original.length) {
          continue;
        }
        if ((applied[v].dx - phase9[v].dx).abs() > 1e-6) {
          triAltered = true;
          break;
        }
      }
      if (triAltered) {
        alteredTris++;
      }
    }

    return {
      'alteredVertexCount': altered,
      'alteredVertexGt5Pct': gt5,
      'alteredVertexGt10Pct': gt10,
      'alteredTriangleCount': alteredTris,
      'meanDistanceToCritical': distances.isEmpty
          ? 0.0
          : distances.reduce((a, b) => a + b) / distances.length,
    };
  }

  static Map<String, dynamic> _summarizeLambda(
    List<Map<String, dynamic>> rows,
    double lambda,
  ) {
    final mode = 'PHASE11_L${_lambdaLabel(lambda)}';
    final modeRows =
        rows.where((r) => r['mode'] == mode).toList(growable: false);

    final at90 = modeRows.firstWhere(
      (r) => (r['faceSlim'] as double) == 0.9,
      orElse: () => modeRows.last,
    );
    final p9 = rows.firstWhere(
      (r) => r['mode'] == 'PHASE9' && (r['faceSlim'] as double) == 0.9,
    );

    return {
      'lambda': lambda,
      'at90': at90,
      'jumpGt2Improvement': (p9['jumpGt2'] as int) - (at90['jumpGt2'] as int),
      'maxJumpImprovement':
          (p9['maxVertexJump'] as double) - (at90['maxVertexJump'] as double),
      'retentionDelta':
          (at90['meanRetention'] as double) - (p9['meanRetention'] as double),
      'alteredVertexDelta':
          (at90['alteredVertexCount'] as int) -
              (p9['constrainedVertexCount'] as int? ?? 0),
      'betterThanPhase9': _isBetterThanPhase9(p9, at90),
    };
  }

  static bool _isBetterThanPhase9(
    Map<String, dynamic> p9,
    Map<String, dynamic> p11,
  ) {
    if ((p11['triangleFoldCount'] as int) != 0) {
      return false;
    }
    if ((p11['minTriangleJ'] as double) <
        _epsilon - TriangleJacobianMath.jacobianTolerance) {
      return false;
    }
    final jumpImproved =
        (p11['jumpGt2'] as int) < (p9['jumpGt2'] as int) ||
            (p11['maxVertexJump'] as double) < (p9['maxVertexJump'] as double);
    final retentionOk =
        (p11['meanRetention'] as double) >=
            (p9['meanRetention'] as double) - 0.02;
    final localityOk =
        (p11['alteredVertexCount'] as int) <=
        ((p9['constrainedVertexCount'] as int? ?? 48) + 10);
    return jumpImproved && retentionOk && localityOk;
  }

  static double _pickBestLambda(List<Map<String, dynamic>> summaries) {
    Map<String, dynamic>? best;
    for (final s in summaries) {
      if (s['betterThanPhase9'] != true) {
        continue;
      }
      if (best == null ||
          (s['jumpGt2Improvement'] as int) >
              (best['jumpGt2Improvement'] as int)) {
        best = s;
      }
    }
    return (best?['lambda'] as double?) ?? 0.5;
  }

  static Map<String, dynamic> _buildConclusion(
    List<Map<String, dynamic>> rows,
    List<Map<String, dynamic>> lambdaSummary,
    double bestLambda,
  ) {
    final p9 = rows.firstWhere(
      (r) => r['mode'] == 'PHASE9' && (r['faceSlim'] as double) == 0.9,
    );
    final p11 = rows.firstWhere(
      (r) =>
          r['mode'] == 'PHASE11_L${_lambdaLabel(bestLambda)}' &&
          (r['faceSlim'] as double) == 0.9,
    );

    final anyBetter =
        lambdaSummary.any((s) => s['betterThanPhase9'] == true);
    final retentionImproved =
        (p11['meanRetention'] as double) > (p9['meanRetention'] as double);
    final jumpImproved =
        (p11['jumpGt2'] as int) < (p9['jumpGt2'] as int) ||
            (p11['maxVertexJump'] as double) < (p9['maxVertexJump'] as double);
    final localityBetter =
        (p11['alteredVertexCount'] as int) <
        (p9['constrainedVertexCount'] as int? ?? 48);

    return {
      'phase11Improved': anyBetter,
      'retentionImproved': retentionImproved,
      'jumpGt2Improved': (p11['jumpGt2'] as int) < (p9['jumpGt2'] as int),
      'maxJumpImproved':
          (p11['maxVertexJump'] as double) < (p9['maxVertexJump'] as double),
      'safetyMaintained':
          (p11['triangleFoldCount'] as int) == 0 &&
              (p11['fieldFoldCount'] as int) == 0,
      'correctionMoreLocal': localityBetter,
      'recommendation': anyBetter && jumpImproved && retentionImproved
          ? 'CONTINUE_PHASE11'
          : 'KEEP_PHASE9',
      'bestLambda': bestLambda,
      'at90Comparison': {
        'phase9': {
          'retention': p9['meanRetention'],
          'maxJump': p9['maxVertexJump'],
          'jumpGt2': p9['jumpGt2'],
          'constrainedVertices': p9['constrainedVertexCount'],
        },
        'phase11': {
          'retention': p11['meanRetention'],
          'maxJump': p11['maxVertexJump'],
          'jumpGt2': p11['jumpGt2'],
          'alteredVertices': p11['alteredVertexCount'],
        },
      },
    };
  }

  static List<Map<String, dynamic>> _hotspotRecords({
    required double intensity,
    required double lambda,
    required TriMesh mesh,
    required List<Offset> original,
    required List<Offset> phase9Deltas,
    required GlobalJacobianDisplacementOptimizerResult result,
  }) {
    final records = <Map<String, dynamic>>[];
    for (final spec in [
      (side: 'right', tri: 547, vertex: 356),
      (side: 'left', tri: 149, vertex: 127),
    ]) {
      final v = spec.vertex;
      if (v >= original.length) {
        continue;
      }
      final jAfter = spec.tri < result.triangleJacobiansAfter.length
          ? result.triangleJacobiansAfter[spec.tri]
          : null;
      final i0 = mesh.indices[spec.tri * 3];
      final i1 = mesh.indices[spec.tri * 3 + 1];
      final i2 = mesh.indices[spec.tri * 3 + 2];
      final jBefore = TriangleJacobianMath.meshTriangleJacobian(
        mesh,
        phase9Deltas,
        i0,
        i1,
        i2,
      );
      final jOrig = TriangleJacobianMath.meshTriangleJacobian(
        mesh,
        original,
        i0,
        i1,
        i2,
      );

      records.add({
        'side': spec.side,
        'faceSlim': intensity,
        'lambda': lambda,
        'triangleId': spec.tri,
        'vertexId': v,
        'originalDx': original[v].dx,
        'phase9Dx': phase9Deltas[v].dx,
        'phase11Dx': result.constrainedDeltas[v].dx,
        'J_original': jOrig,
        'J_phase9': jBefore,
        'J_phase11': jAfter,
        'iterations': result.iterations,
        'converged': result.converged,
      });
    }
    return records;
  }

  static Future<void> _writeComparisonPngs({
    required String outDir,
    required FaceMeshDeformationEngine engine,
    required FaceMeshResult face,
    required TriMesh mesh,
    required Size imageSize,
    required InfluenceMap influence,
    required PersonMask? personMask,
    required int width,
    required int height,
    required TriMeshSpatialIndex sourceIndex,
    required double intensity,
    required double bestLambda,
  }) async {
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
    final label = (intensity * 100).round();
    final original = built.effectiveDeltas;

    final phase9 = GlobalJacobianConstraint.apply(
      mesh: mesh,
      effectiveDeltas: original,
      epsilon: _epsilon,
      enabled: true,
    );
    final phase11 = GlobalJacobianDisplacementOptimizer.apply(
      mesh: mesh,
      originalDelta: original,
      epsilon: _epsilon,
      enabled: true,
      lambda: bestLambda,
    );

    for (final (tag, deltas) in [
      ('baseline', original),
      ('phase9', phase9.constrainedDeltas),
      ('phase11', phase11.constrainedDeltas),
    ]) {
      final image = img.Image(width: width, height: height);
      img.fill(image, color: img.ColorRgb8(16, 16, 20));

      for (var i = 0; i < built.vertexCount; i++) {
        final sx = mesh.vertices[i * 2];
        final sy = mesh.vertices[i * 2 + 1];
        if (sx < 0 || sy < 0 || sx >= width || sy >= height) {
          continue;
        }
        final eff = deltas[i];
        if (eff.distance < 0.15) {
          continue;
        }
        _drawLine(
          image,
          sx.round(),
          sy.round(),
          (sx + eff.dx).round(),
          (sy + eff.dy).round(),
          80,
          200,
          255,
        );
      }

      File('$outDir/debug-face-slim-optimization-$label-$tag.png')
          .writeAsBytesSync(img.encodePng(image));
    }

    // Mapa diferença Phase9 vs Phase11
    final diffImage = img.Image(width: width, height: height);
    img.fill(diffImage, color: img.ColorRgb8(16, 16, 20));
    for (var i = 0; i < built.vertexCount; i++) {
      final sx = mesh.vertices[i * 2];
      final sy = mesh.vertices[i * 2 + 1];
      if (sx < 0 || sy < 0 || sx >= width || sy >= height) {
        continue;
      }
      final d = (phase11.constrainedDeltas[i].dx - phase9.constrainedDeltas[i].dx)
          .abs();
      if (d < 0.01) {
        continue;
      }
      final t = (d / 3.0).clamp(0.0, 1.0);
      final r = (255 * t).round();
      final g = (128 * (1 - t)).round();
      _drawLine(
        diffImage,
        sx.round(),
        sy.round(),
        sx.round(),
        sy.round(),
        r,
        g,
        64,
      );
    }
    File('$outDir/debug-face-slim-optimization-$label-phase9-vs-phase11.png')
        .writeAsBytesSync(img.encodePng(diffImage));
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

  static bool _deltasIdentical(List<Offset> a, List<Offset> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if ((a[i].dx - b[i].dx).abs() > 1e-12 ||
          (a[i].dy - b[i].dy).abs() > 1e-12) {
        return false;
      }
    }
    return true;
  }

  static String _lambdaLabel(double l) =>
      (l * 100).round().toString().padLeft(3, '0');

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

  static void _drawLine(
    img.Image image,
    int x0,
    int y0,
    int x1,
    int y1,
    int r,
    int g,
    int b,
  ) {
    final steps = math.max((x1 - x0).abs(), (y1 - y0).abs());
    if (steps == 0) {
      if (x0 >= 0 && y0 >= 0 && x0 < image.width && y0 < image.height) {
        image.setPixelRgb(x0, y0, r, g, b);
      }
      return;
    }
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = (x0 + (x1 - x0) * t).round();
      final y = (y0 + (y1 - y0) * t).round();
      if (x >= 0 && y >= 0 && x < image.width && y < image.height) {
        image.setPixelRgb(x, y, r, g, b);
      }
    }
  }
}
