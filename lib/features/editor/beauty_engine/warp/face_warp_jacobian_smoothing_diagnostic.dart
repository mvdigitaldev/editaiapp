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
import 'experimental/jacobian_scale_smoothing.dart';
import 'experimental/triangle_jacobian_math.dart';
import 'face_warp_render_contract.dart';
import 'face_warp_renderer.dart' show GeometricSupport;

class FaceWarpJacobianSmoothingDiagnosticResult {
  const FaceWarpJacobianSmoothingDiagnosticResult({
    required this.summary,
    required this.summaryJsonPath,
  });

  final Map<String, dynamic> summary;
  final String summaryJsonPath;
}

/// Fase 10 — smoothing de escalas pós-Phase9.
abstract final class FaceWarpJacobianSmoothingDiagnostic {
  FaceWarpJacobianSmoothingDiagnostic._();

  static const _defaultOutputDir =
      '/Users/leonardo/Documents/Projetos/editaiapp/.cursor';

  static const _intensities = [0.3, 0.5, 0.7, 0.9, 1.0];
  static const _alphas = [0.10, 0.20, 0.30, 0.40];
  static const _epsilon = 0.10;
  static const _pngIntensities = [0.3, 0.5, 0.7, 0.9];

  static Future<FaceWarpJacobianSmoothingDiagnosticResult?> run({
    required FaceMeshResult face,
    required TriMesh mesh,
    required int width,
    required int height,
    PersonMask? personMask,
    String runId = 'jacobian-smoothing-real',
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
      final alphaSummary = <Map<String, dynamic>>[];
      final baselineChecks = <Map<String, dynamic>>[];
      final stabilityTests = <Map<String, dynamic>>[];
      final safetyTests = <Map<String, dynamic>>[];
      final hotspotDebug = <Map<String, dynamic>>[];

      for (final intensity in _intensities) {
        debugPrint('P10 smoothing face_slim=$intensity');

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
          alpha: null,
          mesh: mesh,
          sourceIndex: sourceIndex,
          roi: roi,
          original: original,
          applied: original,
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
          alpha: null,
          mesh: mesh,
          sourceIndex: sourceIndex,
          roi: roi,
          original: original,
          applied: phase9.constrainedDeltas,
          meta: {
            'iterations': phase9.iterations,
            'converged': phase9.converged,
            'constrainedVertexCount': phase9.constrainedVertexCount,
            'constrainedTriangleCount': phase9.constrainedTriangleCount,
          },
        ));

        // Baseline: smoothing disabled == Phase 9
        final disabled = JacobianScaleSmoothing.apply(
          mesh: mesh,
          originalDelta: original,
          phase9Scales: phase9.vertexScales,
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

        for (final alpha in _alphas) {
          final p10 = JacobianScaleSmoothing.apply(
            mesh: mesh,
            originalDelta: original,
            phase9Scales: phase9.vertexScales,
            epsilon: _epsilon,
            alpha: alpha,
            enabled: true,
          );

          var safetyOk = true;
          try {
            JacobianScaleSmoothing.assertTriangleSafety(
              mesh: mesh,
              deltas: p10.constrainedDeltas,
              epsilon: _epsilon,
            );
          } catch (_) {
            safetyOk = false;
          }

          safetyTests.add({
            'faceSlim': intensity,
            'alpha': alpha,
            'safetyOk': safetyOk,
            'violationCount': p10.safetyViolationCount,
          });

          final row = _analyze(
            mode: 'PHASE10_a${_alphaLabel(alpha)}',
            intensity: intensity,
            alpha: alpha,
            mesh: mesh,
            sourceIndex: sourceIndex,
            roi: roi,
            original: original,
            applied: p10.constrainedDeltas,
            meta: {
              'smoothingIterations': p10.smoothingIterations,
              'projectionIterations': p10.projectionIterations,
              'converged': p10.converged,
              'constrainedVertexCount': _countConstrainedVerts(p10.vertexScales),
              'constrainedTriangleCount': _countConstrainedTris(
                mesh,
                p10.vertexScales,
                original.length,
              ),
            },
          );
          sweepRows.add(row);

          if (intensity == 0.9) {
            hotspotDebug.addAll(
              _hotspotRecords(
                intensity: intensity,
                alpha: alpha,
                mesh: mesh,
                original: original,
                phase9Scales: phase9.vertexScales,
                result: p10,
                phase9Deltas: phase9.constrainedDeltas,
              ),
            );
          }

          AgentDebugLog.write(
            location: 'face_warp_jacobian_smoothing_diagnostic.dart:sweep',
            message: 'phase10_jacobian_smoothing_diagnostic',
            hypothesisId: 'P10SM',
            runId: runId,
            phase: '10',
            data: row,
          );
        }
      }

      // Estabilidade @0.9 alpha=0.20
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
      final forward = JacobianScaleSmoothing.applyPipeline(
        mesh: mesh,
        originalDelta: built90.effectiveDeltas,
        epsilon: _epsilon,
        alpha: 0.20,
        smoothingEnabled: true,
      );
      final reverse = JacobianScaleSmoothing.applyPipeline(
        mesh: mesh,
        originalDelta: built90.effectiveDeltas,
        epsilon: _epsilon,
        alpha: 0.20,
        smoothingEnabled: true,
        triangleOrder: List.generate(mesh.triangleCount, (i) => i).reversed
            .toList(),
      );
      final shuffled = List.generate(mesh.triangleCount, (i) => i);
      shuffled.shuffle(math.Random(42));
      final shuffledResult = JacobianScaleSmoothing.applyPipeline(
        mesh: mesh,
        originalDelta: built90.effectiveDeltas,
        epsilon: _epsilon,
        alpha: 0.20,
        smoothingEnabled: true,
        triangleOrder: shuffled,
      );

      stabilityTests.add({
        'faceSlim': 0.9,
        'alpha': 0.20,
        'forwardReverseIdentical': _deltasIdentical(
          forward.constrainedDeltas,
          reverse.constrainedDeltas,
        ),
        'forwardShuffledIdentical': _deltasIdentical(
          forward.constrainedDeltas,
          shuffledResult.constrainedDeltas,
        ),
      });

      for (final alpha in _alphas) {
        alphaSummary.add(_summarizeAlpha(sweepRows, alpha));
      }

      // PNGs com melhor alpha @0.9 por jumpGt2
      final bestAlpha = _pickBestAlpha(alphaSummary);
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
          bestAlpha: bestAlpha,
        );
      }

      final summary = {
        'epsilon': _epsilon,
        'baselinePreserved': baselineChecks.every((r) => r['identityOk'] == true),
        'baselineChecks': baselineChecks,
        'stabilityTests': stabilityTests,
        'safetyTests': safetyTests,
        'allSafetyPassed': safetyTests.every((r) => r['safetyOk'] == true),
        'alphaComparison': alphaSummary,
        'bestAlpha': bestAlpha,
        'hotspotDebug': hotspotDebug,
        'sweep': sweepRows,
      };

      final summaryJsonPath = '$outDir/phase10_jacobian_smoothing_summary.json';
      File(summaryJsonPath).writeAsStringSync(jsonEncode(summary));

      AgentDebugLog.write(
        location: 'face_warp_jacobian_smoothing_diagnostic.dart:run',
        message: 'phase10_jacobian_smoothing_summary',
        hypothesisId: 'P10SM',
        runId: runId,
        phase: '10',
        data: summary,
      );

      return FaceWarpJacobianSmoothingDiagnosticResult(
        summary: summary,
        summaryJsonPath: summaryJsonPath,
      );
    } catch (e, st) {
      debugPrint('P10_FAIL $e\n$st');
      return null;
    }
  }

  static Map<String, dynamic> _analyze({
    required String mode,
    required double intensity,
    required double? alpha,
    required TriMesh mesh,
    required TriMeshSpatialIndex sourceIndex,
    required ({int x0, int y0, int x1, int y1}) roi,
    required List<Offset> original,
    required List<Offset> applied,
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

    return {
      'mode': mode,
      'faceSlim': intensity,
      'alpha': alpha,
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

  static Map<String, dynamic> _summarizeAlpha(
    List<Map<String, dynamic>> rows,
    double alpha,
  ) {
    final mode = 'PHASE10_a${_alphaLabel(alpha)}';
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
      'alpha': alpha,
      'at90': at90,
      'jumpGt2Improvement': (p9['jumpGt2'] as int) - (at90['jumpGt2'] as int),
      'maxJumpImprovement':
          (p9['maxVertexJump'] as double) - (at90['maxVertexJump'] as double),
      'retentionDelta':
          (at90['meanRetention'] as double) - (p9['meanRetention'] as double),
      'betterThanPhase9': _isBetterThanPhase9(p9, at90),
    };
  }

  static bool _isBetterThanPhase9(
    Map<String, dynamic> p9,
    Map<String, dynamic> p10,
  ) {
    if ((p10['triangleFoldCount'] as int) != 0) {
      return false;
    }
    if ((p10['minTriangleJ'] as double) <
        _epsilon - TriangleJacobianMath.jacobianTolerance) {
      return false;
    }
    final jumpImproved =
        (p10['jumpGt2'] as int) < (p9['jumpGt2'] as int) ||
            (p10['maxVertexJump'] as double) < (p9['maxVertexJump'] as double);
    final retentionOk =
        (p10['meanRetention'] as double) >= (p9['meanRetention'] as double) - 0.05;
    return jumpImproved && retentionOk;
  }

  static double _pickBestAlpha(List<Map<String, dynamic>> summaries) {
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
    return (best?['alpha'] as double?) ?? 0.20;
  }

  static List<Map<String, dynamic>> _hotspotRecords({
    required double intensity,
    required double alpha,
    required TriMesh mesh,
    required List<Offset> original,
    required Float32List phase9Scales,
    required JacobianScaleSmoothingResult result,
    required List<Offset> phase9Deltas,
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

      records.add({
        'side': spec.side,
        'faceSlim': intensity,
        'alpha': alpha,
        'triangleId': spec.tri,
        'vertexId': v,
        'scaleBefore': phase9Scales[v],
        'scaleAfter': result.vertexScales[v],
        'displacementBefore': {
          'dx': phase9Deltas[v].dx,
          'dy': phase9Deltas[v].dy,
        },
        'displacementAfter': {
          'dx': result.constrainedDeltas[v].dx,
          'dy': result.constrainedDeltas[v].dy,
        },
        'J_before': jBefore,
        'J_after': jAfter,
        'originalDelta': {'dx': original[v].dx, 'dy': original[v].dy},
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
    required double bestAlpha,
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

    final phase9 = GlobalJacobianConstraint.apply(
      mesh: mesh,
      effectiveDeltas: built.effectiveDeltas,
      epsilon: _epsilon,
      enabled: true,
    );
    final phase10 = JacobianScaleSmoothing.apply(
      mesh: mesh,
      originalDelta: built.effectiveDeltas,
      phase9Scales: phase9.vertexScales,
      epsilon: _epsilon,
      alpha: bestAlpha,
      enabled: true,
    );

    for (final (tag, deltas) in [
      ('phase9', phase9.constrainedDeltas),
      ('phase10', phase10.constrainedDeltas),
    ]) {
      final image = img.Image(width: width, height: height);
      img.fill(image, color: img.ColorRgb8(16, 16, 20));

      for (var i = 0; i < built.vertexCount; i += 2) {
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

      File('$outDir/debug-face-slim-smoothing-$label-$tag.png')
          .writeAsBytesSync(img.encodePng(image));
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

  static int _countConstrainedVerts(Float32List scales) {
    var n = 0;
    for (final s in scales) {
      if (s < 1.0 - 1e-9) {
        n++;
      }
    }
    return n;
  }

  static int _countConstrainedTris(
    TriMesh mesh,
    Float32List scales,
    int vertexCount,
  ) {
    var n = 0;
    for (var t = 0; t < mesh.triangleCount; t++) {
      final i0 = mesh.indices[t * 3];
      final i1 = mesh.indices[t * 3 + 1];
      final i2 = mesh.indices[t * 3 + 2];
      if (i0 >= vertexCount || i1 >= vertexCount || i2 >= vertexCount) {
        continue;
      }
      if (scales[i0] < 1.0 - 1e-9 ||
          scales[i1] < 1.0 - 1e-9 ||
          scales[i2] < 1.0 - 1e-9) {
        n++;
      }
    }
    return n;
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

  static String _alphaLabel(double a) =>
      (a * 100).round().toString().padLeft(2, '0');

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
