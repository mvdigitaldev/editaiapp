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
import 'experimental/jacobian_safe_constraint.dart';
import 'experimental/triangle_jacobian_math.dart';
import 'face_warp_field_vs_mesh_diagnostic.dart';
import 'face_warp_render_contract.dart';
import 'face_warp_renderer.dart' show GeometricSupport;

class FaceWarpGlobalJacobianDiagnosticResult {
  const FaceWarpGlobalJacobianDiagnosticResult({
    required this.summary,
    required this.summaryJsonPath,
  });

  final Map<String, dynamic> summary;
  final String summaryJsonPath;
}

/// Fase 9 — constraint global Jacobi + comparação BASELINE/PHASE8/PHASE9.
abstract final class FaceWarpGlobalJacobianDiagnostic {
  FaceWarpGlobalJacobianDiagnostic._();

  static const _defaultOutputDir =
      '/Users/leonardo/Documents/Projetos/editaiapp/.cursor';

  static const _intensities = [
    0.1, 0.2, 0.25, 0.3, 0.4, 0.5, 0.7, 0.9, 1.0,
  ];

  static const _epsilons = [0.05, 0.10, 0.15, 0.20];
  static const _pngIntensities = [0.3, 0.5, 0.9];

  static Future<FaceWarpGlobalJacobianDiagnosticResult?> run({
    required FaceMeshResult face,
    required TriMesh mesh,
    required int width,
    required int height,
    PersonMask? personMask,
    String runId = 'global-jacobian-real',
    String? outputDirectory,
  }) async {
    if (!kDebugMode) {
      return null;
    }

    try {
      final outDir = outputDirectory ?? _defaultOutputDir;
      Directory(outDir).createSync(recursive: true);

      // Passo 1 — diagnóstico field vs mesh (obrigatório)
      final fieldVsMesh = await FaceWarpFieldVsMeshDiagnostic.run(
        face: face,
        mesh: mesh,
        width: width,
        height: height,
        personMask: personMask,
        outputDirectory: outDir,
      );

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
      final neighbors = _buildVertexNeighbors(mesh);

      final sweepRows = <Map<String, dynamic>>[];
      final epsilonSummary = <Map<String, dynamic>>[];
      final baselineChecks = <Map<String, dynamic>>[];
      final stabilityTests = <Map<String, dynamic>>[];
      final hotspotDebug = <Map<String, dynamic>>[];
      final safetyFailures = <Map<String, dynamic>>[];

      for (final intensity in _intensities) {
        debugPrint('P9 global face_slim=$intensity');

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

        // BASELINE
        sweepRows.add(_analyze(
          mode: 'BASELINE',
          intensity: intensity,
          epsilon: null,
          mesh: mesh,
          sourceIndex: sourceIndex,
          roi: roi,
          original: built.effectiveDeltas,
          applied: built.effectiveDeltas,
          constraintMeta: null,
        ));

        // PHASE8 @0.10 (referência)
        if (intensity >= 0.3) {
          final p8 = JacobianSafeConstraint.apply(
            mesh: mesh,
            effectiveDeltas: built.effectiveDeltas,
            epsilon: 0.10,
            enabled: true,
          );
          sweepRows.add(_analyze(
            mode: 'PHASE8_J010',
            intensity: intensity,
            epsilon: 0.10,
            mesh: mesh,
            sourceIndex: sourceIndex,
            roi: roi,
            original: built.effectiveDeltas,
            applied: p8.constrainedDeltas,
            constraintMeta: {
              'constrainedTriangleCount': p8.constrainedTriangleCount,
              'constrainedVertexCount': p8.constrainedVertexCount,
              'iterations': 8,
              'converged': null,
            },
          ));
        }

        for (final epsilon in _epsilons) {
          final result = GlobalJacobianConstraint.apply(
            mesh: mesh,
            effectiveDeltas: built.effectiveDeltas,
            epsilon: epsilon,
            enabled: true,
          );

          final row = _analyze(
            mode: 'PHASE9_J${_epsLabel(epsilon)}',
            intensity: intensity,
            epsilon: epsilon,
            mesh: mesh,
            sourceIndex: sourceIndex,
            roi: roi,
            original: built.effectiveDeltas,
            applied: result.constrainedDeltas,
            constraintMeta: {
              'constrainedTriangleCount': result.constrainedTriangleCount,
              'constrainedVertexCount': result.constrainedVertexCount,
              'iterations': result.iterations,
              'converged': result.converged,
              'finalViolationCount': result.finalViolationCount,
            },
          );
          sweepRows.add(row);

          if (result.finalViolationCount > 0 ||
              TriangleJacobianMath.countBelow(
                    result.triangleJacobiansAfter,
                    0,
                  ) >
                  0) {
            safetyFailures.add({
              'faceSlim': intensity,
              'epsilon': epsilon,
              'finalViolationCount': result.finalViolationCount,
              'triangleFoldCount': TriangleJacobianMath.countBelow(
                result.triangleJacobiansAfter,
                0,
              ),
              'minTriangleJ': TriangleJacobianMath.minJacobian(
                result.triangleJacobiansAfter,
              ),
            });
          }

          if (intensity == 0.9) {
            hotspotDebug.addAll(
              _hotspotRecords(
                intensity: intensity,
                epsilon: epsilon,
                mesh: mesh,
                neighbors: neighbors,
                original: built.effectiveDeltas,
                result: result,
                supportWeights: built.supportWeights,
                vertexField: built.vertexField,
              ),
            );
          }

          AgentDebugLog.write(
            location: 'face_warp_global_jacobian_diagnostic.dart:sweep',
            message: 'phase9_global_jacobian_diagnostic',
            hypothesisId: 'P9GJ',
            runId: runId,
            phase: '9',
            data: row,
          );
        }

        // Baseline identity
        final disabled = GlobalJacobianConstraint.apply(
          mesh: mesh,
          effectiveDeltas: built.effectiveDeltas,
          epsilon: 0.10,
          enabled: false,
        );
        baselineChecks.add({
          'faceSlim': intensity,
          'identityOk': _deltasIdentical(
            built.effectiveDeltas,
            disabled.constrainedDeltas,
          ),
        });
      }

      // Estabilidade: ordem de triângulos @0.9 ε=0.10
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
      final forward = GlobalJacobianConstraint.apply(
        mesh: mesh,
        effectiveDeltas: built90.effectiveDeltas,
        epsilon: 0.10,
        enabled: true,
      );
      final reverseOrder = List.generate(mesh.triangleCount, (i) => i).reversed
          .toList();
      final reverse = GlobalJacobianConstraint.apply(
        mesh: mesh,
        effectiveDeltas: built90.effectiveDeltas,
        epsilon: 0.10,
        enabled: true,
        triangleOrder: reverseOrder,
      );
      final shuffled = List.generate(mesh.triangleCount, (i) => i);
      shuffled.shuffle(math.Random(42));
      final shuffledResult = GlobalJacobianConstraint.apply(
        mesh: mesh,
        effectiveDeltas: built90.effectiveDeltas,
        epsilon: 0.10,
        enabled: true,
        triangleOrder: shuffled,
      );
      final orderStable = _deltasIdentical(
        forward.constrainedDeltas,
        reverse.constrainedDeltas,
      ) &&
          _deltasIdentical(
            forward.constrainedDeltas,
            shuffledResult.constrainedDeltas,
          );
      stabilityTests.add({
        'faceSlim': 0.9,
        'epsilon': 0.10,
        'forwardReverseIdentical': _deltasIdentical(
          forward.constrainedDeltas,
          reverse.constrainedDeltas,
        ),
        'forwardShuffledIdentical': _deltasIdentical(
          forward.constrainedDeltas,
          shuffledResult.constrainedDeltas,
        ),
        'orderStable': orderStable,
        'forwardIterations': forward.iterations,
        'reverseIterations': reverse.iterations,
        'shuffledIterations': shuffledResult.iterations,
      });

      for (final eps in _epsilons) {
        epsilonSummary.add(_summarizeEpsilon(sweepRows, eps));
      }

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
          roi: roi,
          intensity: intensity,
        );
      }

      final summary = {
        'fieldVsMesh': fieldVsMesh?['divergenceExplanation'],
        'baselinePreserved': baselineChecks.every((r) => r['identityOk'] == true),
        'baselineChecks': baselineChecks,
        'stabilityTests': stabilityTests,
        'orderStable': orderStable,
        'epsilonComparison': epsilonSummary,
        'safetyFailures': safetyFailures,
        'hotspotDebug': hotspotDebug,
        'sweep': sweepRows,
      };

      final summaryJsonPath = '$outDir/phase9_global_jacobian_summary.json';
      File(summaryJsonPath).writeAsStringSync(jsonEncode(summary));

      AgentDebugLog.write(
        location: 'face_warp_global_jacobian_diagnostic.dart:run',
        message: 'phase9_global_jacobian_summary',
        hypothesisId: 'P9GJ',
        runId: runId,
        phase: '9',
        data: summary,
      );

      return FaceWarpGlobalJacobianDiagnosticResult(
        summary: summary,
        summaryJsonPath: summaryJsonPath,
      );
    } catch (e, st) {
      debugPrint('P9_FAIL $e\n$st');
      return null;
    }
  }

  static Map<String, dynamic> _analyze({
    required String mode,
    required double intensity,
    required double? epsilon,
    required TriMesh mesh,
    required TriMeshSpatialIndex sourceIndex,
    required ({int x0, int y0, int x1, int y1}) roi,
    required List<Offset> original,
    required List<Offset> applied,
    required Map<String, dynamic>? constraintMeta,
  }) {
    final meshJ = TriangleJacobianMath.allMeshJacobians(mesh, applied);
    final fieldScan = _scanFieldJacobian(
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
      'epsilon': epsilon,
      'minFieldJ': fieldScan.minJ,
      'minTriangleJ': TriangleJacobianMath.minJacobian(meshJ),
      'foldCount': fieldScan.foldCount,
      'triangleFoldCount': TriangleJacobianMath.countBelow(meshJ, 0),
      'meanRetention': retention['mean'],
      'p50Retention': retention['p50'],
      'p95Retention': retention['p95'],
      'maxDisplacement': disp.max,
      'meanDisplacement': disp.mean,
      'maxVertexJump': jumps.maxJump,
      'meanVertexJump': jumps.meanJump,
      'p95VertexJump': jumps.p95Jump,
      'jumpGt2': jumps.gt2,
      'jumpGt5': jumps.gt5,
      'jumpGt10': jumps.gt10,
      if (constraintMeta != null) ...constraintMeta,
    };
  }

  static Map<String, dynamic> _summarizeEpsilon(
    List<Map<String, dynamic>> rows,
    double epsilon,
  ) {
    final mode = 'PHASE9_J${_epsLabel(epsilon)}';
    final modeRows =
        rows.where((r) => r['mode'] == mode).toList(growable: false);

    double? maxIntensityNoTriFold;
    for (final r in modeRows) {
      if ((r['triangleFoldCount'] as int) == 0 &&
          (r['minTriangleJ'] as double) >=
              epsilon - TriangleJacobianMath.jacobianTolerance) {
        maxIntensityNoTriFold = r['faceSlim'] as double;
      }
    }

    final at90 = modeRows.firstWhere(
      (r) => (r['faceSlim'] as double) == 0.9,
      orElse: () => modeRows.last,
    );

    return {
      'epsilon': epsilon,
      'maxFaceSlimWithoutTriangleFold': maxIntensityNoTriFold,
      'at90': at90,
    };
  }

  static List<Map<String, dynamic>> _hotspotRecords({
    required double intensity,
    required double epsilon,
    required TriMesh mesh,
    required List<Set<int>> neighbors,
    required List<Offset> original,
    required GlobalJacobianConstraintResult result,
    required Float32List supportWeights,
    required dynamic vertexField,
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
      final neighborTris = <int>{};
      for (final nv in neighbors[v]) {
        for (var t = 0; t < mesh.triangleCount; t++) {
          final verts = [
            mesh.indices[t * 3],
            mesh.indices[t * 3 + 1],
            mesh.indices[t * 3 + 2],
          ];
          if (verts.contains(v) && verts.contains(nv)) {
            neighborTris.add(t);
          }
        }
      }

      records.add({
        'side': spec.side,
        'faceSlim': intensity,
        'epsilon': epsilon,
        'triangleId': spec.tri,
        'vertexId': v,
        'neighboringTriangles': neighborTris.take(12).toList(),
        'sourceX': mesh.vertices[v * 2],
        'sourceY': mesh.vertices[v * 2 + 1],
        'originalDelta': {'dx': original[v].dx, 'dy': original[v].dy},
        'constrainedDelta': {
          'dx': result.constrainedDeltas[v].dx,
          'dy': result.constrainedDeltas[v].dy,
        },
        'scale': result.vertexScales[v],
        'J_before': spec.tri < result.triangleJacobiansBefore.length
            ? result.triangleJacobiansBefore[spec.tri]
            : null,
        'J_after': spec.tri < result.triangleJacobiansAfter.length
            ? result.triangleJacobiansAfter[spec.tri]
            : null,
        'supportWeight': supportWeights[v],
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
    required ({int x0, int y0, int x1, int y1}) roi,
    required double intensity,
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
    const eps = 0.10;

    final modes = <({String tag, List<Offset> deltas})>[
      (tag: 'baseline', deltas: built.effectiveDeltas),
      (
        tag: 'phase8',
        deltas: JacobianSafeConstraint.apply(
          mesh: mesh,
          effectiveDeltas: built.effectiveDeltas,
          epsilon: eps,
          enabled: true,
        ).constrainedDeltas,
      ),
      (
        tag: 'phase9',
        deltas: GlobalJacobianConstraint.apply(
          mesh: mesh,
          effectiveDeltas: built.effectiveDeltas,
          epsilon: eps,
          enabled: true,
        ).constrainedDeltas,
      ),
    ];

    for (final m in modes) {
      final meshJ = TriangleJacobianMath.allMeshJacobians(mesh, m.deltas);
      final foldTris = TriangleJacobianMath.countBelow(meshJ, 0);

      final image = img.Image(width: width, height: height);
      img.fill(image, color: img.ColorRgb8(16, 16, 20));

      for (var t = 0; t < mesh.triangleCount; t++) {
        if (meshJ[t] >= 0) {
          continue;
        }
        final c = TriangleJacobianMath.triangleCentroid(mesh, t);
        final ix = c.cx.round().clamp(0, width - 1);
        final iy = c.cy.round().clamp(0, height - 1);
        for (var dy = -2; dy <= 2; dy++) {
          for (var dx = -2; dx <= 2; dx++) {
            final x = ix + dx;
            final y = iy + dy;
            if (x >= 0 && y >= 0 && x < width && y < height) {
              image.setPixelRgb(x, y, 180, 40, 40);
            }
          }
        }
      }

      for (var i = 0; i < built.vertexCount; i += 2) {
        final sx = mesh.vertices[i * 2];
        final sy = mesh.vertices[i * 2 + 1];
        if (sx < 0 || sy < 0 || sx >= width || sy >= height) {
          continue;
        }
        final eff = m.deltas[i];
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

      File('$outDir/debug-face-slim-global-${label}-${m.tag}-j010.png')
          .writeAsBytesSync(img.encodePng(image));
      debugPrint('PNG $label ${m.tag} meshFolds=$foldTris');
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
    const h = 2.0;
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
          h: h,
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
    double meanJump,
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
      meanJump: jumps.isEmpty
          ? 0.0
          : jumps.reduce((a, b) => a + b) / jumps.length,
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

  static String _epsLabel(double eps) =>
      eps.toStringAsFixed(2).replaceAll('.', '');

  static List<Set<int>> _buildVertexNeighbors(TriMesh mesh) {
    final n = mesh.vertices.length ~/ 2;
    final neighbors = List.generate(n, (_) => <int>{});
    for (var t = 0; t < mesh.triangleCount; t++) {
      final i0 = mesh.indices[t * 3];
      final i1 = mesh.indices[t * 3 + 1];
      final i2 = mesh.indices[t * 3 + 2];
      if (i0 < n && i1 < n && i2 < n) {
        neighbors[i0].addAll([i1, i2]);
        neighbors[i1].addAll([i0, i2]);
        neighbors[i2].addAll([i0, i1]);
      }
    }
    return neighbors;
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
