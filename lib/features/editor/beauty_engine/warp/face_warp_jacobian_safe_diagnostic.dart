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
import 'anatomy/vertex_role_map.dart';
import 'experimental/jacobian_safe_constraint.dart';
import 'face_warp_render_contract.dart';
import 'face_warp_renderer.dart' show GeometricSupport;

/// Resultado Fase 8 — protótipo Jacobian-safe.
class FaceWarpJacobianSafeDiagnosticResult {
  const FaceWarpJacobianSafeDiagnosticResult({
    required this.summary,
    required this.summaryJsonPath,
  });

  final Map<String, dynamic> summary;
  final String summaryJsonPath;
}

/// Fase 8 — sweep epsilon × face_slim com constraint experimental.
abstract final class FaceWarpJacobianSafeDiagnostic {
  FaceWarpJacobianSafeDiagnostic._();

  static const _defaultOutputDir =
      '/Users/leonardo/Documents/Projetos/editaiapp/.cursor';

  static const _intensities = [
    0.0, 0.1, 0.2, 0.25, 0.3, 0.4, 0.5, 0.7, 0.9, 1.0,
  ];

  static const _epsilons = [0.05, 0.10, 0.20, 0.30];
  static const _pngIntensities = [0.3, 0.5, 0.9];
  static const _pngEpsilons = [0.10, 0.20, 0.30];

  static const _diagTriangleRight = 547;
  static const _diagVertexRight = 356;
  static const _diagTriangleLeft = 149;
  static const _diagVertexLeft = 127;
  static const _hotspotX = 532.5;
  static const _hotspotY = 439.5;

  static Future<FaceWarpJacobianSafeDiagnosticResult?> run({
    required FaceMeshResult face,
    required TriMesh mesh,
    required int width,
    required int height,
    PersonMask? personMask,
    String runId = 'jacobian-safe-real',
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
      final neighbors = _buildVertexNeighbors(mesh);
      final zoneLookup = _buildVertexZoneLookup();

      final sweepRows = <Map<String, dynamic>>[];
      final epsilonSummary = <Map<String, dynamic>>[];
      final baselineChecks = <Map<String, dynamic>>[];
      final safetyFailures = <Map<String, dynamic>>[];
      final hotspotDebug = <Map<String, dynamic>>[];

      for (final intensity in _intensities) {
        debugPrint('P8 jacobian-safe face_slim=$intensity');

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

        final baselineRow = _analyzeMode(
          mode: 'BASELINE',
          intensity: intensity,
          epsilon: null,
          mesh: mesh,
          sourceIndex: sourceIndex,
          roi: roi,
          neighbors: neighbors,
          effectiveDeltas: built.effectiveDeltas,
          supportWeights: built.supportWeights,
          vertexField: built.vertexField,
          vertexCount: built.vertexCount,
          zoneLookup: zoneLookup,
          constraintResult: null,
        );
        sweepRows.add(baselineRow);

        final disabled = JacobianSafeConstraint.apply(
          mesh: mesh,
          effectiveDeltas: built.effectiveDeltas,
          epsilon: 0.10,
          enabled: false,
        );
        final identityOk = _deltasIdentical(
          built.effectiveDeltas,
          disabled.constrainedDeltas,
        );
        baselineChecks.add({
          'faceSlim': intensity,
          'identityOk': identityOk,
          'maxDeltaDiff': identityOk
              ? 0.0
              : _maxDeltaDiff(
                  built.effectiveDeltas,
                  disabled.constrainedDeltas,
                ),
        });

        for (final epsilon in _epsilons) {
          final constrained = JacobianSafeConstraint.apply(
            mesh: mesh,
            effectiveDeltas: built.effectiveDeltas,
            epsilon: epsilon,
            enabled: true,
          );

          final row = _analyzeMode(
            mode: 'SAFE_J_${_epsLabel(epsilon)}',
            intensity: intensity,
            epsilon: epsilon,
            mesh: mesh,
            sourceIndex: sourceIndex,
            roi: roi,
            neighbors: neighbors,
            effectiveDeltas: built.effectiveDeltas,
            supportWeights: built.supportWeights,
            vertexField: built.vertexField,
            vertexCount: built.vertexCount,
            zoneLookup: zoneLookup,
            constraintResult: constrained,
          );
          sweepRows.add(row);

          final minJAfter = row['minJ_after'] as double;
          if (minJAfter < epsilon - JacobianSafeConstraint.jacobianTolerance) {
            safetyFailures.add({
              'faceSlim': intensity,
              'epsilon': epsilon,
              'minJ_after': minJAfter,
              'failedTriangles': _failedTriangles(
                constrained.triangleJacobiansAfter,
                epsilon,
              ),
            });
          }

          if (intensity == 0.9) {
            hotspotDebug.addAll(
              _hotspotRecords(
                intensity: intensity,
                epsilon: epsilon,
                mesh: mesh,
                original: built.effectiveDeltas,
                constrained: constrained,
                supportWeights: built.supportWeights,
                vertexField: built.vertexField,
              ),
            );
          }

          AgentDebugLog.write(
            location: 'face_warp_jacobian_safe_diagnostic.dart:sweep',
            message: 'phase8_jacobian_safe_diagnostic',
            hypothesisId: 'P8JS',
            runId: runId,
            phase: '8',
            data: row,
          );
        }
      }

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
        'baselinePreserved': baselineChecks.every((r) => r['identityOk'] == true),
        'baselineChecks': baselineChecks,
        'epsilonComparison': epsilonSummary,
        'safetyFailures': safetyFailures,
        'hotspotDebug': hotspotDebug,
        'sweep': sweepRows,
        'diagnosticTriangles': {
          'right': _diagTriangleRight,
          'rightVertex': _diagVertexRight,
          'left': _diagTriangleLeft,
          'leftVertex': _diagVertexLeft,
          'hotspot': {'x': _hotspotX, 'y': _hotspotY},
        },
      };

      final summaryJsonPath = '$outDir/phase8_jacobian_safe_summary.json';
      File(summaryJsonPath).writeAsStringSync(jsonEncode(summary));

      AgentDebugLog.write(
        location: 'face_warp_jacobian_safe_diagnostic.dart:run',
        message: 'phase8_jacobian_safe_summary',
        hypothesisId: 'P8JS',
        runId: runId,
        phase: '8',
        data: summary,
      );

      return FaceWarpJacobianSafeDiagnosticResult(
        summary: summary,
        summaryJsonPath: summaryJsonPath,
      );
    } catch (e, st) {
      debugPrint('P8_FAIL $e\n$st');
      return null;
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

  static Map<String, dynamic> _analyzeMode({
    required String mode,
    required double intensity,
    required double? epsilon,
    required TriMesh mesh,
    required TriMeshSpatialIndex sourceIndex,
    required ({int x0, int y0, int x1, int y1}) roi,
    required List<Set<int>> neighbors,
    required List<Offset> effectiveDeltas,
    required Float32List supportWeights,
    required dynamic vertexField,
    required int vertexCount,
    required Map<int, String> zoneLookup,
    required JacobianSafeConstraintResult? constraintResult,
  }) {
    final applied = constraintResult?.constrainedDeltas ?? effectiveDeltas;

    final fieldBefore = _scanFieldJacobian(
      sourceIndex: sourceIndex,
      deltas: effectiveDeltas,
      vertexCount: vertexCount,
      roi: roi,
    );
    final fieldAfter = _scanFieldJacobian(
      sourceIndex: sourceIndex,
      deltas: applied,
      vertexCount: vertexCount,
      roi: roi,
    );

    final triJBefore = constraintResult?.triangleJacobiansBefore ??
        JacobianSafeConstraint.apply(
          mesh: mesh,
          effectiveDeltas: effectiveDeltas,
          epsilon: 0,
          enabled: false,
        ).triangleJacobiansBefore;
    final triJAfter = constraintResult?.triangleJacobiansAfter ?? triJBefore;

    final retention = _retentionStats(effectiveDeltas, applied);
    final dispBefore = _displacementStats(effectiveDeltas);
    final dispAfter = _displacementStats(applied);
    final jumps = _meshEdgeJumps(mesh, effectiveDeltas, applied, vertexCount);

    return {
      'mode': mode,
      'faceSlim': intensity,
      'epsilon': epsilon,
      'intensity': intensity,
      'minJ_before': fieldBefore.minJ,
      'minJ_after': fieldAfter.minJ,
      'minTriangleJ_before': JacobianSafeConstraint.minTriangleJacobian(triJBefore),
      'minTriangleJ_after': JacobianSafeConstraint.minTriangleJacobian(triJAfter),
      'foldCountBefore': fieldBefore.foldCount,
      'foldCountAfter': fieldAfter.foldCount,
      'triangleFoldCountBefore':
          JacobianSafeConstraint.countFoldTriangles(triJBefore),
      'triangleFoldCountAfter':
          JacobianSafeConstraint.countFoldTriangles(triJAfter),
      'maxDisplacementBefore': dispBefore.max,
      'maxDisplacementAfter': dispAfter.max,
      'meanDisplacementBefore': dispBefore.mean,
      'meanDisplacementAfter': dispAfter.mean,
      'displacementRetention': retention,
      'maxVertexJump': jumps.maxJump,
      'jumpGt5': jumps.gt5,
      'jumpGt10': jumps.gt10,
      'triangleCount': mesh.triangleCount,
      'constrainedTriangleCount':
          constraintResult?.constrainedTriangleCount ?? 0,
      'constrainedVertexCount': constraintResult?.constrainedVertexCount ?? 0,
    };
  }

  static Map<String, dynamic> _summarizeEpsilon(
    List<Map<String, dynamic>> rows,
    double epsilon,
  ) {
    final mode = 'SAFE_J_${_epsLabel(epsilon)}';
    final modeRows =
        rows.where((r) => r['mode'] == mode).toList(growable: false);

    double? maxFaceSlimWithoutFold;
    for (final r in modeRows) {
      if ((r['foldCountAfter'] as int) == 0 &&
          (r['minJ_after'] as double) >= epsilon - 1e-4) {
        maxFaceSlimWithoutFold = r['faceSlim'] as double;
      }
    }

    final at90 = modeRows.firstWhere(
      (r) => (r['faceSlim'] as double) == 0.9,
      orElse: () => modeRows.last,
    );
    final ret = at90['displacementRetention'] as Map<String, dynamic>;

    return {
      'epsilon': epsilon,
      'maxFaceSlimWithoutFold': maxFaceSlimWithoutFold,
      'minJ_at90': at90['minJ_after'],
      'foldCount_at90': at90['foldCountAfter'],
      'retention_at90': ret['mean'],
      'retention_p50_at90': ret['p50'],
      'maxJump_at90': at90['maxVertexJump'],
      'constrainedTriangles_at90': at90['constrainedTriangleCount'],
    };
  }

  static List<Map<String, dynamic>> _hotspotRecords({
    required double intensity,
    required double epsilon,
    required TriMesh mesh,
    required List<Offset> original,
    required JacobianSafeConstraintResult constrained,
    required Float32List supportWeights,
    required dynamic vertexField,
  }) {
    final records = <Map<String, dynamic>>[];
    for (final spec in [
      (
        side: 'right',
        tri: _diagTriangleRight,
        vertex: _diagVertexRight,
      ),
      (
        side: 'left',
        tri: _diagTriangleLeft,
        vertex: _diagVertexLeft,
      ),
    ]) {
      final v = spec.vertex;
      if (v >= original.length) {
        continue;
      }
      final orig = original[v];
      final safe = constrained.constrainedDeltas[v];
      final scale = constrained.vertexScales[v];
      final triJBefore = spec.tri < constrained.triangleJacobiansBefore.length
          ? constrained.triangleJacobiansBefore[spec.tri]
          : null;
      final triJAfter = spec.tri < constrained.triangleJacobiansAfter.length
          ? constrained.triangleJacobiansAfter[spec.tri]
          : null;
      records.add({
        'side': spec.side,
        'faceSlim': intensity,
        'epsilon': epsilon,
        'triangleId': spec.tri,
        'vertexId': v,
        'sourceX': mesh.vertices[v * 2],
        'sourceY': mesh.vertices[v * 2 + 1],
        'originalDelta': {'dx': orig.dx, 'dy': orig.dy},
        'constrainedDelta': {'dx': safe.dx, 'dy': safe.dy},
        'scale': scale,
        'J_before': triJBefore,
        'J_after': triJAfter,
        'supportWeight': supportWeights[v],
        'zoneWeight': vertexField.displacementAt(v).distance > 1e-9
            ? safe.distance / vertexField.displacementAt(v).distance
            : 0.0,
        'faceSlimIntensity': intensity,
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

    final modes = <({String tag, List<Offset> deltas})>[
      (tag: 'baseline', deltas: built.effectiveDeltas),
    ];
    for (final eps in _pngEpsilons) {
      final r = JacobianSafeConstraint.apply(
        mesh: mesh,
        effectiveDeltas: built.effectiveDeltas,
        epsilon: eps,
        enabled: true,
      );
      modes.add((tag: 'j${_epsLabel(eps)}', deltas: r.constrainedDeltas));
    }

    for (final m in modes) {
      final scan = _scanFieldJacobian(
        sourceIndex: sourceIndex,
        deltas: m.deltas,
        vertexCount: built.vertexCount,
        roi: roi,
      );
      final image = img.Image(width: width, height: height);
      img.fill(image, color: img.ColorRgb8(16, 16, 20));

      for (final hs in scan.hotspots.take(200)) {
        final ix = hs.px.round().clamp(0, width - 1);
        final iy = hs.py.round().clamp(0, height - 1);
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

      File('$outDir/debug-face-slim-jacobian-${label}-${m.tag}.png')
          .writeAsBytesSync(img.encodePng(image));
    }
  }

  static ({
    double minJ,
    int foldCount,
    List<({double px, double py, double j})> hotspots,
  }) _scanFieldJacobian({
    required TriMeshSpatialIndex sourceIndex,
    required List<Offset> deltas,
    required int vertexCount,
    required ({int x0, int y0, int x1, int y1}) roi,
  }) {
    const gridStep = 4.0;
    const h = 2.0;
    final jValues = <double>[];
    final hotspots = <({double px, double py, double j})>[];

    for (var y = roi.y0 + gridStep; y <= roi.y1 - gridStep; y += gridStep) {
      for (var x = roi.x0 + gridStep; x <= roi.x1 - gridStep; x += gridStep) {
        final j = _fieldJacobianAt(
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
        jValues.add(j.j);
        if (j.j <= 0) {
          hotspots.add(j);
        }
      }
    }

    jValues.sort();
    return (
      minJ: jValues.isEmpty ? 1.0 : jValues.first,
      foldCount: hotspots.length,
      hotspots: hotspots,
    );
  }

  static ({double px, double py, double j})? _fieldJacobianAt({
    required TriMeshSpatialIndex sourceIndex,
    required List<Offset> deltas,
    required int vertexCount,
    required double px,
    required double py,
    required double h,
  }) {
    Offset? disp(double x, double y) {
      final tri = sourceIndex.locateTriangleIndex(x, y);
      if (tri == null) {
        return null;
      }
      final hit = sourceIndex.barycentricInTriangle(tri, x, y);
      if (hit == null) {
        return null;
      }
      var dx = 0.0;
      var dy = 0.0;
      for (final (i, w) in [
        (hit.i0, hit.w0),
        (hit.i1, hit.w1),
        (hit.i2, hit.w2),
      ]) {
        if (i >= vertexCount) {
          return null;
        }
        dx += w * deltas[i].dx;
        dy += w * deltas[i].dy;
      }
      return Offset(dx, dy);
    }

    final c = disp(px, py);
    final xp = disp(px + h, py);
    final xm = disp(px - h, py);
    final yp = disp(px, py + h);
    final ym = disp(px, py - h);
    if (c == null || xp == null || xm == null || yp == null || ym == null) {
      return null;
    }

    final dudx = (xp.dx - xm.dx) / (2 * h);
    final dudy = (yp.dx - ym.dx) / (2 * h);
    final dvdx = (xp.dy - xm.dy) / (2 * h);
    final dvdy = (yp.dy - ym.dy) / (2 * h);
    final j = (1 + dudx) * (1 + dvdy) - dudy * dvdx;
    return (px: px, py: py, j: j);
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
      return {
        'mean': 1.0,
        'p50': 1.0,
        'p95': 1.0,
        'min': 1.0,
        'max': 1.0,
      };
    }
    return {
      'mean': ratios.reduce((a, b) => a + b) / ratios.length,
      'p50': _percentile(ratios, 0.5),
      'p95': _percentile(ratios, 0.95),
      'min': ratios.first,
      'max': ratios.last,
    };
  }

  static ({double max, double mean}) _displacementStats(List<Offset> deltas) {
    var max = 0.0;
    var sum = 0.0;
    var n = 0;
    for (final d in deltas) {
      final m = d.distance;
      if (m > max) {
        max = m;
      }
      sum += m;
      n++;
    }
    return (max: max, mean: n == 0 ? 0.0 : sum / n);
  }

  static ({
    double maxJump,
    int gt5,
    int gt10,
  }) _meshEdgeJumps(
    TriMesh mesh,
    List<Offset> before,
    List<Offset> after,
    int vertexCount,
  ) {
    final seen = <String>{};
    var maxJump = 0.0;
    var gt5 = 0;
    var gt10 = 0;

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

        final dx = (after[a].dx - after[b].dx) - (before[a].dx - before[b].dx);
        final dy = (after[a].dy - after[b].dy) - (before[a].dy - before[b].dy);
        final jump = math.sqrt(dx * dx + dy * dy);
        if (jump > maxJump) {
          maxJump = jump;
        }
        if (jump > 5) {
          gt5++;
        }
        if (jump > 10) {
          gt10++;
        }
      }
    }

    return (maxJump: maxJump, gt5: gt5, gt10: gt10);
  }

  static List<int> _failedTriangles(List<double> jacobians, double epsilon) {
    final out = <int>[];
    for (var i = 0; i < jacobians.length; i++) {
      if (jacobians[i] < epsilon - JacobianSafeConstraint.jacobianTolerance) {
        out.add(i);
        if (out.length >= 20) {
          break;
        }
      }
    }
    return out;
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

  static double _maxDeltaDiff(List<Offset> a, List<Offset> b) {
    var max = 0.0;
    for (var i = 0; i < a.length && i < b.length; i++) {
      max = math.max(max, (a[i] - b[i]).distance);
    }
    return max;
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

  static Map<int, String> _buildVertexZoneLookup() {
    final map = <int, String>{};
    for (final entry in VertexRoleMap.zoneLandmarks.entries) {
      for (final idx in entry.value) {
        map[idx] = entry.key.name;
      }
    }
    return map;
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
